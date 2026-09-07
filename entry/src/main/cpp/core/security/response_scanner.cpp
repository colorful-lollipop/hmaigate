// response_scanner.cpp —— 上游响应流式安全扫描器实现（M4，纯逻辑、宿主可单测）
//
// 刻意不含 mongoose / hilog：与 request_pipeline 同一原则，头文件与实现都能被
// 宿主侧（MinGW g++）直接编译进单测；overflow 等需要打日志的事件经 ScanOutcome
// 标志位上抛给 proxy_server。
#include "security/response_scanner.h"

#include "plugin_manager.h"     // aigate::PluginManager（响应侧插件钩子链）
#include "security_detector.h"  // aigate::SecurityDetector（内置检测引擎）

namespace hmsec {

namespace {

// 找最早的事件边界：\r\n\r\n 或 \n\n。返回边界起始位置与整段（含边界）长度。
bool FindEventBoundary(const std::string& buf, size_t& segEnd) {
  size_t crlf = buf.find("\r\n\r\n");
  size_t lf = buf.find("\n\n");
  if (crlf == std::string::npos && lf == std::string::npos) return false;
  if (crlf != std::string::npos && (lf == std::string::npos || crlf <= lf)) {
    segEnd = crlf + 4;
  } else {
    segEnd = lf + 2;
  }
  return true;
}

}  // namespace

bool ResponseScanner::ScanSegment(const std::string& seg, std::string& reason) {
  // HTTP 响应头块（以状态行开头）跳过扫描：响应头来自可信上游，
  // 且 password_leak 的"关键词+冒号"模式可能误伤正常响应头（如 x-token: ...）。
  if (seg.compare(0, 5, "HTTP/") == 0) return true;

  auto& pluginManager = aigate::PluginManager::GetInstance();

  // 第 1 段：内置检测器。与请求路径同构——直接调用并受插件表
  // builtin-security-detector 开关门控，避免与适配器 vtable 重复检测。
  // 只认映射为 BLOCK 的级别（如 malicious_tool_use、password_leak）；
  // WARN 级（如 context_injection，响应侧本也不检测）放行。
  if (pluginManager.IsPluginEnabled(aigate::kBuiltinSecurityPluginId)) {
    aigate::HttpResponse resp;
    resp.statusCode = 200;
    resp.body = seg;
    auto& detector = aigate::SecurityDetector::GetInstance();
    aigate::DetectionResult r = detector.DetectResponse(resp);
    if (detector.IsBlocking(r)) {
      reason = r.message;
      return false;
    }
  }

  // 第 2 段：已启用文件来源 security 插件的 detect_response 链（M2 留的 ABI 位，
  // M4 接线）。任一插件返回 BLOCK(2) 即阻断；WARN(1) 放行（仅留 ABI）。
  // 持锁快照在 GetEnabledResponseHooks 内完成，这里在锁外执行插件代码。
  char pluginReason[512];
  for (const auto& hook : pluginManager.GetEnabledResponseHooks()) {
    pluginReason[0] = '\0';
    int verdict = hook.detectResponse(seg.c_str(), pluginReason, sizeof(pluginReason));
    if (verdict == AIGATE_DETECT_BLOCK) {
      reason = pluginReason[0] != '\0' ? pluginReason : ("blocked by plugin " + hook.id);
      return false;
    }
  }
  return true;
}

ScanOutcome ResponseScanner::Feed(const char* data, size_t len) {
  ScanOutcome out;
  if (blocked_) {
    out.blocked = true;
    out.reason = reason_;
    return out;
  }
  if (overflowed_) {
    // 已 fail-open：后续字节直通，不再缓冲（本连接放弃检测，换取不卡流）
    out.release.assign(data, len);
    return out;
  }

  buf_.append(data, len);

  // 逐个切出完整事件扫描；不完整尾部留缓冲区
  size_t segEnd = 0;
  while (FindEventBoundary(buf_, segEnd)) {
    std::string seg = buf_.substr(0, segEnd);
    std::string reason;
    if (!ScanSegment(seg, reason)) {
      // 阻断：本次已确认的前缀照常放行（out.release），调用方随后发错误事件并关连接
      blocked_ = true;
      reason_ = reason;
      out.blocked = true;
      out.reason = reason;
      buf_.clear();
      return out;
    }
    out.release += seg;
    buf_.erase(0, segEnd);
  }

  // 聚合超上限：fail-open——未扫部分直接放行，只置位一次 overflow 标志
  if (buf_.size() > limit_) {
    out.release += buf_;
    buf_.clear();
    overflowed_ = true;
    if (!overflowReported_) {
      overflowReported_ = true;
      out.overflow = true;
    }
  }
  return out;
}

ScanOutcome ResponseScanner::Flush() {
  ScanOutcome out;
  if (blocked_) {
    out.blocked = true;
    out.reason = reason_;
    return out;
  }
  if (buf_.empty()) return out;

  if (!overflowed_) {
    // 非 SSE 响应的完整 body / SSE 的不完整尾部：整体扫一次
    std::string reason;
    if (!ScanSegment(buf_, reason)) {
      blocked_ = true;
      reason_ = reason;
      out.blocked = true;
      out.reason = reason;
      buf_.clear();
      return out;
    }
  }
  out.release = buf_;
  buf_.clear();
  return out;
}

}  // namespace hmsec
