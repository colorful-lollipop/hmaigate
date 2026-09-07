// router.h —— 多上游规则路由表（M3）
//
// ArkTS 侧把用户配置的路由规则序列化成 JSON，经 NAPI setRouteRules 原子推给本模块；
// 转发管线（request_pipeline ResolveRoute）对每个请求做协议识别后查表：
// 命中用规则上游，未命中回退默认单一上游（ProxyServer::CurrentUpstream）。
// 规则表为空 = 关闭路由，行为与 M3 之前完全一致。
//
// 匹配语义（与 ArkTS 侧约定）：规则命中当且仅当
//   (modelPrefix == "" || 请求 model 以它开头)
//   && (protocol == "any"/"" || == 识别出的协议字符串)
//   && (pathPrefix == "" || 请求 uri 以它开头)
// 多条命中时 priority 数值大者优先；同优先级按数组顺序（先出现者胜）。
#pragma once

#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "protocol/protocol_adapter.h"  // LlmProtocol
#include "proxy/proxy_server.h"         // UpstreamConfig

namespace hmsec {

// 一条路由规则。字段与 ArkTS 推送的 JSON 一一对应。
struct RouteRule {
  std::string id;
  std::string name;
  int priority = 0;
  std::string modelPrefix;   // "" = 不限模型
  std::string protocol;      // "any" | "anthropic" | "openai" | "gemini"（"" 视同 any）
  std::string pathPrefix;    // "" = 不限路径
  UpstreamConfig upstream;
};

// 单条规则匹配判定（纯函数，拆出来便于单测）。
bool Matches(const RouteRule& rule, LlmProtocol proto, const std::string& model,
             const std::string& uri);

class Router {
 public:
  static Router& Instance();

  // 从 JSON 原子替换整张路由表。非法 JSON 返回 false 且不动旧表；
  // 空数组 "[]" 合法——清空路由表（关闭路由，回退默认单一上游）。
  bool SetRulesFromJson(const std::string& json);

  // 查表：命中返回规则 upstream 指针（ruleId 非空时顺带带出命中规则 id，供日志），
  // 未命中返回 nullptr。返回指针的有效性：规则表以不可变快照整体 swap，
  // 本函数把当前快照存入 lastRead_ 保活，调用方（mongoose 工作线程，单线程）
  // 在下一次 Route 调用前拷贝使用是安全的。
  const UpstreamConfig* Route(LlmProtocol proto, const std::string& model,
                              const std::string& uri,
                              std::string* ruleId = nullptr) const;

  size_t RuleCount() const;

 private:
  Router() = default;
  Router(const Router&) = delete;
  Router& operator=(const Router&) = delete;

  mutable std::mutex mutex_;
  // 不可变规则表快照：替换即 swap shared_ptr，读侧拿到的旧快照不受影响（热更新安全）。
  std::shared_ptr<const std::vector<RouteRule>> rules_;
  // 最近一次 Route 使用的快照，保活用（见 Route 注释）。
  mutable std::shared_ptr<const std::vector<RouteRule>> lastRead_;
};

}  // namespace hmsec
