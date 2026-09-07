// router.cpp —— 多上游规则路由表实现（M3）
#include "proxy/router.h"

#include "json_scan.h"  // hmsec::JsonCursor（R2：手写最小 JSON 扫描的公共实现）

namespace hmsec {

namespace {

bool StartsWith(const std::string& s, const std::string& prefix) {
  return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
}

// —— 手写最小 JSON 解析（R2 起用 json_scan.h 的 JsonCursor）——
// 不引入 JSON 库的理由见 json_scan.h 头部注释。解析是严格的：任何结构性错误都让
// SetRulesFromJson 整体失败（返回 false、不动旧表），未知字段一律跳过（向后兼容）。

bool ParseUpstream(JsonCursor& ps, UpstreamConfig& up) {
  if (!ps.Consume('{')) return false;
  up.set = true;
  if (ps.Consume('}')) return true;  // 空对象：baseUrl 校验在外层做
  while (true) {
    std::string key;
    if (!ps.ParseString(key)) return false;
    if (!ps.Consume(':')) return false;
    if (key == "baseUrl") {
      if (!ps.ParseString(up.baseUrl)) return false;
    } else if (key == "apiKey") {
      if (!ps.ParseString(up.apiKey)) return false;
    } else if (key == "apiKeyField") {
      if (!ps.ParseString(up.apiKeyField)) return false;
    } else if (key == "model") {
      if (!ps.ParseString(up.model)) return false;
    } else {
      if (!ps.SkipValue()) return false;  // 未知字段：跳过（向后兼容）
    }
    if (ps.Consume(',')) continue;
    return ps.Consume('}');
  }
}

bool ParseRule(JsonCursor& ps, RouteRule& rule) {
  if (!ps.Consume('{')) return false;
  bool hasUpstream = false;
  if (ps.Consume('}')) return false;  // 空对象规则无意义
  while (true) {
    std::string key;
    if (!ps.ParseString(key)) return false;
    if (!ps.Consume(':')) return false;
    if (key == "id") {
      if (!ps.ParseString(rule.id)) return false;
    } else if (key == "name") {
      if (!ps.ParseString(rule.name)) return false;
    } else if (key == "priority") {
      long v = 0;
      if (!ps.ParseInt(v)) return false;
      rule.priority = static_cast<int>(v);
    } else if (key == "modelPrefix") {
      if (!ps.ParseString(rule.modelPrefix)) return false;
    } else if (key == "protocol") {
      if (!ps.ParseString(rule.protocol)) return false;
    } else if (key == "pathPrefix") {
      if (!ps.ParseString(rule.pathPrefix)) return false;
    } else if (key == "upstream") {
      if (!ParseUpstream(ps, rule.upstream)) return false;
      hasUpstream = true;
    } else {
      if (!ps.SkipValue()) return false;
    }
    if (ps.Consume(',')) continue;
    if (!ps.Consume('}')) return false;
    break;
  }
  // upstream 缺省或 baseUrl 为空：规则无法路由，整张表按非法处理（不动旧表）
  return hasUpstream && !rule.upstream.baseUrl.empty();
}

// 解析整张规则表；成功时 out 被替换为解析结果（可能为空数组）。
bool ParseRules(const std::string& json, std::vector<RouteRule>& out) {
  JsonCursor ps{json.c_str(), json.size(), 0};
  if (!ps.Consume('[')) return false;
  out.clear();
  if (ps.Consume(']')) return ps.Eof();  // 空数组 = 合法（关闭路由）
  while (true) {
    RouteRule r;
    if (!ParseRule(ps, r)) return false;
    out.push_back(std::move(r));
    if (ps.Consume(',')) continue;
    if (!ps.Consume(']')) return false;
    return ps.Eof();
  }
}

}  // namespace

bool Matches(const RouteRule& rule, LlmProtocol proto, const std::string& model,
             const std::string& uri) {
  if (!rule.modelPrefix.empty() && !StartsWith(model, rule.modelPrefix)) return false;
  if (!rule.protocol.empty() && rule.protocol != "any" &&
      rule.protocol != ProtocolToString(proto)) {
    return false;
  }
  if (!rule.pathPrefix.empty() && !StartsWith(uri, rule.pathPrefix)) return false;
  return true;
}

Router& Router::Instance() {
  static Router inst;
  return inst;
}

bool Router::SetRulesFromJson(const std::string& json) {
  // 先在锁外解析（JSON 可能较大），成功才持锁整体 swap——非法输入绝不动旧表
  std::vector<RouteRule> parsed;
  if (!ParseRules(json, parsed)) return false;
  std::lock_guard<std::mutex> lk(mutex_);
  rules_ = std::make_shared<const std::vector<RouteRule>>(std::move(parsed));
  return true;
}

const UpstreamConfig* Router::Route(LlmProtocol proto, const std::string& model,
                                    const std::string& uri, std::string* ruleId) const {
  std::lock_guard<std::mutex> lk(mutex_);
  // 保活当前快照：swap 后旧表仍存活，返回的指针在调用方（工作线程，单线程）
  // 下一次 Route 之前拷贝使用是安全的。
  lastRead_ = rules_;
  if (!lastRead_) return nullptr;
  const RouteRule* best = nullptr;
  for (const RouteRule& r : *lastRead_) {
    if (!Matches(r, proto, model, uri)) continue;
    // 严格大于才替换：priority 大者优先；同优先级保留先出现者（数组顺序）
    if (best == nullptr || r.priority > best->priority) best = &r;
  }
  if (best == nullptr) return nullptr;
  if (ruleId != nullptr) *ruleId = best->id;
  return &best->upstream;
}

size_t Router::RuleCount() const {
  std::lock_guard<std::mutex> lk(mutex_);
  return rules_ ? rules_->size() : 0;
}

}  // namespace hmsec
