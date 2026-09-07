// response_scanner.h —— 上游响应的流式安全扫描器（M4，纯逻辑、无网络库依赖，宿主可单测）
//
// 背景：proxy_server 原本对上游响应字节做零拷贝直通（SSE 流式友好）。M4 响应
// 侧安全检测要求先扫再放行，本组件承接缓冲与切分：
//
//   - 按事件边界（\n\n 或 \r\n\r\n）切分。SSE 流（data: 行 + 空行分隔）每个完整
//     事件扫描通过后立即放行，转发延迟 ≈ 一个事件；不完整尾部留在缓冲区。
//     HTTP 响应头块以 \r\n\r\n 结尾，天然就是"第一个事件"——但它以 "HTTP/" 开头，
//     按可信上游内容跳过扫描直接放行（也避免 password_leak 的"关键词+冒号"模式
//     误伤正常响应头）。
//   - 非 SSE 响应（body 里没有空行边界）自然聚合在缓冲区，Flush（上游关闭）时
//     整体扫描后放行——非 SSE 客户端本就等完整 body，聚合不增加感知延迟。
//   - 聚合上限 256KB（fail-open 取舍：超出上限说明不是典型 LLM 文本响应，
//     继续缓冲既撑内存又让客户端干等；超过后未扫部分直接放行并置 overflow 标志，
//     由调用方打 hilog warn。之后本连接退化为直通，不再缓冲）。
//
// 扫描内容：aigate::SecurityDetector::DetectResponse（受插件表
// builtin-security-detector 开关门控；只认映射为 BLOCK 的级别，WARN 只放行）
// + PluginManager 已启用文件来源 security 插件的 detect_response 链。
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace hmsec {

// 一次 Feed/Flush 的结果。
struct ScanOutcome {
  std::string release;   // 可安全转发给本地客户端的字节（确认安全的前缀；可能为空）
  bool blocked = false;  // 命中阻断：release 是阻断点之前已确认的字节，reason 是原因
  bool overflow = false; // 本次发生了超上限 fail-open（调用方打 hilog warn，只置位一次）
  std::string reason;    // 阻断原因（规则 message / 插件 reason）
};

class ResponseScanner {
 public:
  // 非典型响应的聚合上限。256KB 的取舍：正常 LLM 单事件/整页 JSON 远低于此；
  // 超过即 fail-open 直通（宁可漏检不可卡死流）。
  static constexpr size_t kDefaultAggregateLimit = 256 * 1024;

  explicit ResponseScanner(size_t aggregateLimit = kDefaultAggregateLimit)
      : limit_(aggregateLimit) {}

  // 喂入上游读到的字节，返回本次可放行的字节与阻断结论。
  ScanOutcome Feed(const char* data, size_t len);

  // 收尾（上游连接关闭前调用）：扫描并放行缓冲区里剩余的全部字节。
  ScanOutcome Flush();

 private:
  // 扫描一个完整片段。命中应阻断内容时返回 false 并给出原因。
  bool ScanSegment(const std::string& seg, std::string& reason);

  size_t limit_;
  std::string buf_;        // 未确认安全的缓冲（不完整事件/非 SSE 聚合）
  bool blocked_ = false;   // 已阻断：后续 Feed 直接回报阻断（调用方随即关连接）
  bool overflowed_ = false;  // 已 fail-open：后续字节直通不再缓冲
  bool overflowReported_ = false;
  std::string reason_;     // 阻断原因（blocked_ 后保持，供重复查询）
};

}  // namespace hmsec
