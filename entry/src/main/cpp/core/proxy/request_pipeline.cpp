// request_pipeline.cpp —— 转发请求处理管线实现（纯逻辑，无网络库依赖）
//
// 步骤实现自 proxy_server.cpp 原请求处理分支的内联逻辑平移而来，
// 刻意不含任何网络库类型：头文件可被宿主侧（MinGW g++）直接编译进单测。
#include "proxy/request_pipeline.h"

#include "proxy/router.h"       // hmsec::Router（M3：规则路由表）
#include "security_detector.h"  // aigate::SecurityDetector（真实检测引擎，由步骤 2 调用）
#include "plugin_manager.h"     // aigate::PluginManager（M2：动态库安全插件链）
#include "security/password_leak_audit.h"  // 请求侧密码泄露提醒（异步，不阻断）

namespace hmsec {

RouteResult ResolveRoute(const UpstreamConfig& defaultUp, const std::string& method,
                         const std::string& uri, const std::string& body) {
  RouteResult r;
  // M3：先识别协议 + 提取 model，再查规则路由表。
  // 规则表为空时 Route 必未命中 → 回退默认上游，行为与 M3 之前完全一致。
  r.protocol = DetectProtocol(method, uri, body);
  r.model = ExtractMetadata(r.protocol, uri, body).model;
  const UpstreamConfig* routed =
      Router::Instance().Route(r.protocol, r.model, uri, &r.ruleId);
  const UpstreamConfig& up = (routed != nullptr) ? *routed : defaultUp;
  if (!up.set) {
    r.error = RouteError::kNoUpstream;
    return r;
  }
  r.target = ResolveTarget(up.baseUrl, uri);
  if (!r.target.valid) {
    r.error = RouteError::kBadUpstreamUrl;
    return r;
  }
  r.upstream = up;  // 命中规则的指针在上锁快照内，此处拷入结果后不再使用
  r.ok = true;
  return r;
}

bool SecurityCheckRequest(bool securityEnabled, const std::string& /*method*/,
                          const std::string& /*uri*/, const std::string& body) {
  if (!securityEnabled) return true;
  auto& pluginManager = aigate::PluginManager::GetInstance();

  // 第 1 段：内置检测器。它同时以内置插件 builtin-security-detector 出现在
  // 插件表里——此处直接调用（而非经适配器 vtable）并受其 enabled 门控，
  // 避免同一检测经两条路径跑两遍。
  if (pluginManager.IsPluginEnabled(aigate::kBuiltinSecurityPluginId)) {
    // 构造「脱敏」请求：只检测 body，刻意不把请求头放进检测范围，
    // 避免合法鉴权头（Bearer/x-api-key）被 password_leak 规则误杀。
    aigate::HttpRequest req;
    req.url = "/";
    req.body = body;
    auto& detector = aigate::SecurityDetector::GetInstance();
    aigate::DetectionResult r = detector.DetectRequest(req);
    // M4 起尊重「级别→动作」映射：只阻断映射为 BLOCK 的命中
    //（password_leak/prompt_injection 为 BLOCK，保持既有行为；
    // M4 新增的 context_injection 为 CRITICAL→WARN，命中只进 hitCount 不拦请求）。
    if (detector.IsBlocking(r)) {
      return false;
    }
  }

  // 第 2 段：M2 动态库 security 插件链（只查请求体，与第 1 段同语义）。
  // 任一插件返回 BLOCK(2) 即拦截；WARN(1) 放行（警告原因本期不上送 UI，仅留 ABI）。
  // 注意持锁快照已在 GetEnabledSecurityHooks 内完成，这里在锁外执行插件代码。
  char reason[512];
  for (const auto& hook : pluginManager.GetEnabledSecurityHooks()) {
    reason[0] = '\0';
    int verdict = hook.detectRequest(body.c_str(), reason, sizeof(reason));
    if (verdict == AIGATE_DETECT_BLOCK) return false;
  }

  // 响应侧检测（M4 已接线）不在本步骤：见 proxy_server.cpp ClientEv 的
  // ResponseScanner（流式按事件边界扫描，与请求侧同检测器 + 同插件链）。
  return true;
}

void QueuePasswordLeakAudit(const std::string& body, const std::string& protocol,
                            const std::string& model) {
  auto& pluginManager = aigate::PluginManager::GetInstance();
  if (!pluginManager.IsPluginEnabled(aigate::kPasswordLeakAuditPluginId)) return;
  auto& audit = aigate::PasswordLeakAudit::GetInstance();
  if (!audit.IsEnabled()) return;
  audit.Enqueue(body, protocol, model);
}

std::string BuildRequest(const std::string& method, const HeaderList& headers,
                         const std::string& body, const ParsedUrl& target,
                         const UpstreamConfig& up) {
  std::string out;
  // 请求行：方法 + 目标路径
  out += method;
  out += ' ';
  out += target.path;
  out += " HTTP/1.1\r\n";

  // 复制请求头：跳过 Host / Content-Length / Connection，以及客户端自带的鉴权头
  for (const auto& h : headers) {
    const std::string lower = ToLower(h.first);
    if (lower == "host" || lower == "content-length" || lower == "connection") continue;
    if (IsAuthHeaderName(lower)) continue;  // 用配置的 Key 替换
    out += h.first;
    out += ": ";
    out += h.second;
    out += "\r\n";
  }

  // Host 头按上游重写
  out += "Host: ";
  out += target.host;
  if (target.port != 0 && target.port != DefaultPort(target.tls)) {
    out += ':';
    out += std::to_string(target.port);
  }
  out += "\r\n";

  // 注入配置的鉴权头（依据 apiKeyField 决定头名/形式；Claude Code 仅指向本地代理，
  // 真实 Key 只在网关侧持有）
  out += BuildAuthHeader(up.apiKeyField, up.apiKey);

  out += "Content-Length: ";
  out += std::to_string(body.size());
  out += "\r\nConnection: close\r\n\r\n";
  out += body;
  return out;
}

}  // namespace hmsec
