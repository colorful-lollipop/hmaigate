// request_pipeline.h —— 转发请求处理管线（纯逻辑步骤，无网络库依赖，便于宿主侧单测）
//
// 把 proxy_server.cpp 的请求处理拆成三个边界清晰、可独立测试的步骤：
//   1. ResolveRoute         选择上游并解析转发目标（M3：协议识别 + Router 规则路由，未命中回退默认单一上游）
//   2. SecurityCheckRequest 请求体安全检测（只查 body，刻意不查请求头）
//   3. BuildRequest         构造转发字节（重写 Host、剔 hop-by-hop/客户端鉴权头、注入网关 Key）
// proxy_server.cpp 只保留事件分发、连接生命周期与统计计数，
// 在请求入口顺序调用本管线。
#pragma once

#include <string>
#include <utility>
#include <vector>

#include "protocol/protocol_adapter.h"  // LlmProtocol（M3：路由诊断随结果携带）
#include "proxy/proxy_server.h"  // UpstreamConfig
#include "proxy/upstream.h"      // ParsedUrl

namespace hmsec {

// 请求头名值对（已从 HTTP 消息剥离为纯字符串，网络库类型不进本模块）。
using HeaderList = std::vector<std::pair<std::string, std::string>>;

// ResolveRoute 的失败类别：调用方据此映射 502 文案与 lastError（保持既有行为）。
enum class RouteError {
  kNone,           // 成功
  kNoUpstream,     // 未配置上游
  kBadUpstreamUrl  // 上游 baseUrl 非法（与请求路径拼接后解析失败）
};

// 路由结果。规则路由未命中（或规则表为空）时回退默认单一上游
//（ProxyServer::CurrentUpstream），行为与 M3 之前一致。
struct RouteResult {
  bool ok = false;
  RouteError error = RouteError::kNone;
  UpstreamConfig upstream;  // 命中的上游配置（ok=false 时无效）
  ParsedUrl target;         // 转发目标（ok=false 时无效）
  // M3 路由诊断（供 proxy_server 打 hilog；绝不包含 apiKey）
  std::string ruleId;  // 命中的规则 id；空 = 走默认上游（规则表为空或未命中）
  std::string model;   // 从请求体/URI 提取的模型名（可能为空）
  LlmProtocol protocol = LlmProtocol::kUnknown;
};

// 步骤 1：路由解析。defaultUp 由调用方在互斥锁保护下读取后传入（见
// ProxyServer::CurrentUpstream）；M3 起先对 method/uri/body 做协议识别 + 元数据
// 提取，再查 Router 规则表——命中用规则上游，未命中/规则表为空回退 defaultUp。
RouteResult ResolveRoute(const UpstreamConfig& defaultUp, const std::string& method,
                         const std::string& uri, const std::string& body);

// 步骤 2：请求体安全检测。只检测 body——刻意排除请求头，
// 避免合法 Bearer/x-api-key 被误判为密码泄露。securityEnabled=false 时直接放行。
// M2 起检测分两段：内置 SecurityDetector（受插件表 builtin-security-detector 开关门控）
// + 已启用动态库 security 插件的 detect_request 链（任一 BLOCK 即拦截）。
// M4 起尊重「级别→动作」映射：只阻断映射为 BLOCK 的命中（WARN 级只进 hitCount）。
// 响应侧检测 M4 已接线，在 proxy_server.cpp 的 ResponseScanner（不在本步骤）。
// 返回 true=放行，false=拦截。
bool SecurityCheckRequest(bool securityEnabled, const std::string& method,
                          const std::string& uri, const std::string& body);

// 请求侧密码泄露提醒：在同步安全检查通过后调用。仅复制受限大小正文进入异步
// password-leak-audit 队列，绝不改变当前请求的放行/阻断结果。protocol/model 只写入
// 脱敏告警元数据，调用方传 RouteResult 中已经提取好的值。
void QueuePasswordLeakAudit(const std::string& body, const std::string& protocol,
                            const std::string& model);

// 步骤 3：构造转发给上游的完整请求字节：
//  - 请求行：方法 + 目标路径
//  - 重写 Host（按上游 host；非默认端口才带端口）
//  - 剔除 hop-by-hop 头（Host/Content-Length/Connection）与客户端自带的鉴权头
//  - 按 up.apiKeyField 注入网关侧鉴权头（BuildAuthHeader；无 Key/未知字段不注入）
//  - 末尾补 Content-Length 与 Connection: close，再接原始 body
std::string BuildRequest(const std::string& method, const HeaderList& headers,
                         const std::string& body, const ParsedUrl& target,
                         const UpstreamConfig& up);

}  // namespace hmsec
