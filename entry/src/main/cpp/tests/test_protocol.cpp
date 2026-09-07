// test_protocol.cpp —— M3 协议识别 / 元数据提取 / 规则路由的宿主侧单元测试
//
// 覆盖：DetectProtocol 识别矩阵（路径特征 + body 签名兜底 + unknown）、
// ExtractMetadata（model/stream/gemini URI 兜底）、Router 匹配语义
//（前缀/协议/路径组合、优先级、同优先级数组顺序、非法 JSON 不动旧表、空数组关闭路由）。
#include "../include/protocol/protocol_adapter.h"
#include "../include/proxy/router.h"
#include "hm_test.h"

using hmsec::LlmProtocol;
using hmsec::RequestMetadata;
using hmsec::RouteRule;
using hmsec::Router;

// ---------- DetectProtocol：路径特征 ----------

static void test_DetectProtocol_anthropic_path() {
  EQ_BOOL(hmsec::DetectProtocol("POST", "/v1/messages", "") == LlmProtocol::kAnthropic,
          true);
  // count_tokens 同属 anthropic 形态
  EQ_BOOL(hmsec::DetectProtocol("POST", "/v1/messages/count_tokens?x=1", "{}") ==
              LlmProtocol::kAnthropic,
          true);
}

static void test_DetectProtocol_openai_path() {
  EQ_BOOL(hmsec::DetectProtocol("POST", "/v1/chat/completions", "") ==
              LlmProtocol::kOpenAI,
          true);
  EQ_BOOL(hmsec::DetectProtocol("POST", "/v1/responses", "") == LlmProtocol::kOpenAI,
          true);
}

static void test_DetectProtocol_gemini_path() {
  EQ_BOOL(hmsec::DetectProtocol(
              "POST", "/v1beta/models/gemini-2.5-pro:generateContent", "") ==
              LlmProtocol::kGemini,
          true);
  EQ_BOOL(hmsec::DetectProtocol(
              "POST", "/v1beta/models/gemini-2.5-pro:streamGenerateContent?alt=sse",
              "") == LlmProtocol::kGemini,
          true);
}

static void test_DetectProtocol_unknown_path_and_empty_body() {
  EQ_BOOL(hmsec::DetectProtocol("GET", "/v1/models", "") == LlmProtocol::kUnknown,
          true);
}

// ---------- DetectProtocol：body 签名兜底 ----------

static void test_DetectProtocol_body_sniff_anthropic() {
  // 自定义/反代路径：max_tokens + messages 组合 → anthropic
  EQ_BOOL(hmsec::DetectProtocol("POST", "/custom/endpoint",
                                "{\"max_tokens\":1024,\"messages\":[]}") ==
              LlmProtocol::kAnthropic,
          true);
}

static void test_DetectProtocol_body_sniff_openai() {
  // 只有 messages（无 max_tokens）→ openai
  EQ_BOOL(hmsec::DetectProtocol("POST", "/custom/endpoint",
                                "{\"messages\":[{\"role\":\"user\"}]}") ==
              LlmProtocol::kOpenAI,
          true);
}

static void test_DetectProtocol_body_sniff_gemini() {
  EQ_BOOL(hmsec::DetectProtocol("POST", "/custom/endpoint",
                                "{\"contents\":[{\"parts\":[{\"text\":\"hi\"}]}]}") ==
              LlmProtocol::kGemini,
          true);
}

static void test_DetectProtocol_body_no_signature() {
  EQ_BOOL(hmsec::DetectProtocol("POST", "/custom/endpoint", "{\"foo\":1}") ==
              LlmProtocol::kUnknown,
          true);
}

static void test_ProtocolToString() {
  EQ_STR(hmsec::ProtocolToString(LlmProtocol::kAnthropic), "anthropic");
  EQ_STR(hmsec::ProtocolToString(LlmProtocol::kOpenAI), "openai");
  EQ_STR(hmsec::ProtocolToString(LlmProtocol::kGemini), "gemini");
  EQ_STR(hmsec::ProtocolToString(LlmProtocol::kUnknown), "unknown");
}

// ---------- ExtractMetadata ----------

static void test_ExtractMetadata_anthropic_model_and_stream() {
  RequestMetadata m = hmsec::ExtractMetadata(
      LlmProtocol::kAnthropic, "/v1/messages",
      "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"stream\":true,"
      "\"messages\":[]}");
  EQ_STR(m.model, "claude-sonnet-4");
  EQ_BOOL(m.stream, true);
}

static void test_ExtractMetadata_openai_default_stream_false() {
  RequestMetadata m = hmsec::ExtractMetadata(LlmProtocol::kOpenAI,
                                             "/v1/chat/completions",
                                             "{\"model\":\"gpt-5\",\"messages\":[]}");
  EQ_STR(m.model, "gpt-5");
  EQ_BOOL(m.stream, false);
}

static void test_ExtractMetadata_stream_options_not_stream() {
  // openai 的 stream_options 不得被误认作 stream
  RequestMetadata m = hmsec::ExtractMetadata(
      LlmProtocol::kOpenAI, "/v1/chat/completions",
      "{\"model\":\"gpt-5\",\"stream_options\":{\"include_usage\":true}}");
  EQ_STR(m.model, "gpt-5");
  EQ_BOOL(m.stream, false);
}

static void test_ExtractMetadata_gemini_uri_fallback() {
  // gemini 的 model 在 uri 里；body 没有 "model" 字段
  RequestMetadata m = hmsec::ExtractMetadata(
      LlmProtocol::kGemini, "/v1beta/models/gemini-2.5-pro:generateContent",
      "{\"contents\":[]}");
  EQ_STR(m.model, "gemini-2.5-pro");
}

static void test_ExtractMetadata_missing_model() {
  RequestMetadata m =
      hmsec::ExtractMetadata(LlmProtocol::kAnthropic, "/v1/messages",
                             "{\"max_tokens\":1,\"messages\":[]}");
  EQ_STR(m.model, "");
}

// ---------- Router：匹配语义 ----------

// 造一条规则 JSON（字段按跨层契约 schema）
static std::string ruleJson(const std::string& id, int priority,
                            const std::string& modelPrefix,
                            const std::string& protocol,
                            const std::string& pathPrefix,
                            const std::string& baseUrl) {
  return "{\"id\":\"" + id + "\",\"name\":\"n-" + id + "\",\"priority\":" +
         std::to_string(priority) + ",\"modelPrefix\":\"" + modelPrefix +
         "\",\"protocol\":\"" + protocol + "\",\"pathPrefix\":\"" + pathPrefix +
         "\",\"upstream\":{\"baseUrl\":\"" + baseUrl +
         "\",\"apiKey\":\"k-" + id +
         "\",\"apiKeyField\":\"ANTHROPIC_AUTH_TOKEN\",\"model\":\"\"}}";
}

static void test_Router_model_prefix_and_fallback() {
  Router& r = Router::Instance();
  std::string json = "[" +
      ruleJson("glm", 10, "glm", "any", "", "https://open.bigmodel.cn/api/anthropic") +
      "," +
      ruleJson("def", 5, "", "any", "", "https://api.anthropic.com") + "]";
  EQ_BOOL(r.SetRulesFromJson(json), true);
  EQ_INT(r.RuleCount(), 2);

  // glm 前缀命中 r1；其他 model 落到兜底规则
  const hmsec::UpstreamConfig* up =
      r.Route(LlmProtocol::kAnthropic, "glm-4.6", "/v1/messages");
  EQ_BOOL(up != nullptr, true);
  EQ_STR(up->baseUrl, "https://open.bigmodel.cn/api/anthropic");
  up = r.Route(LlmProtocol::kAnthropic, "claude-sonnet-4", "/v1/messages");
  EQ_BOOL(up != nullptr, true);
  EQ_STR(up->baseUrl, "https://api.anthropic.com");
}

static void test_Router_protocol_filter() {
  Router& r = Router::Instance();
  std::string json = "[" +
      ruleJson("oai", 10, "", "openai", "", "https://api.openai.com") + "]";
  EQ_BOOL(r.SetRulesFromJson(json), true);

  // 协议不匹配 → 未命中
  EQ_BOOL(r.Route(LlmProtocol::kAnthropic, "glm-4.6", "/v1/messages") == nullptr,
          true);
  // 协议匹配 → 命中
  const hmsec::UpstreamConfig* up =
      r.Route(LlmProtocol::kOpenAI, "gpt-5", "/v1/chat/completions");
  EQ_BOOL(up != nullptr, true);
  EQ_STR(up->apiKey, "k-oai");  // upstream 字段完整解析（含 apiKey/apiKeyField）
  EQ_STR(up->apiKeyField, "ANTHROPIC_AUTH_TOKEN");
  EQ_BOOL(up->set, true);
}

static void test_Router_path_prefix() {
  Router& r = Router::Instance();
  std::string json = "[" +
      ruleJson("chat", 10, "", "any", "/v1/chat", "https://api.openai.com") + "]";
  EQ_BOOL(r.SetRulesFromJson(json), true);

  EQ_BOOL(r.Route(LlmProtocol::kOpenAI, "gpt-5", "/v1/chat/completions") != nullptr,
          true);
  EQ_BOOL(r.Route(LlmProtocol::kAnthropic, "x", "/v1/messages") == nullptr, true);
}

static void test_Router_priority_and_tie_order() {
  Router& r = Router::Instance();
  // 两条都命中：priority 大者胜
  std::string json = "[" + ruleJson("lo", 1, "", "any", "", "https://lo.example.com") +
                     "," + ruleJson("hi", 9, "", "any", "", "https://hi.example.com") +
                     "]";
  EQ_BOOL(r.SetRulesFromJson(json), true);
  const hmsec::UpstreamConfig* up = r.Route(LlmProtocol::kUnknown, "", "/anything");
  EQ_BOOL(up != nullptr, true);
  EQ_STR(up->baseUrl, "https://hi.example.com");

  // 同优先级：数组顺序（先出现者胜）
  json = "[" + ruleJson("first", 5, "", "any", "", "https://first.example.com") + "," +
         ruleJson("second", 5, "", "any", "", "https://second.example.com") + "]";
  EQ_BOOL(r.SetRulesFromJson(json), true);
  up = r.Route(LlmProtocol::kUnknown, "", "/anything");
  EQ_BOOL(up != nullptr, true);
  EQ_STR(up->baseUrl, "https://first.example.com");
}

static void test_Router_rule_id_out_param() {
  Router& r = Router::Instance();
  std::string json = "[" + ruleJson("rid", 10, "glm", "any", "",
                                    "https://open.bigmodel.cn/api/anthropic") + "]";
  EQ_BOOL(r.SetRulesFromJson(json), true);
  std::string id;
  const hmsec::UpstreamConfig* up =
      r.Route(LlmProtocol::kAnthropic, "glm-4.6", "/v1/messages", &id);
  EQ_BOOL(up != nullptr, true);
  EQ_STR(id, "rid");
}

static void test_Router_invalid_json_keeps_old_table() {
  Router& r = Router::Instance();
  std::string good = "[" + ruleJson("keep", 10, "", "any", "",
                                    "https://keep.example.com") + "]";
  EQ_BOOL(r.SetRulesFromJson(good), true);
  EQ_INT(r.RuleCount(), 1);

  // 各种非法 JSON：返回 false 且旧表不动
  EQ_BOOL(r.SetRulesFromJson("{oops"), false);
  EQ_BOOL(r.SetRulesFromJson(""), false);
  EQ_BOOL(r.SetRulesFromJson("[{\"id\":\"x\"}]"), false);  // 缺 upstream
  EQ_BOOL(r.SetRulesFromJson("[{\"id\":\"x\",\"upstream\":{}}]"), false);  // 空 baseUrl
  EQ_INT(r.RuleCount(), 1);
  const hmsec::UpstreamConfig* up = r.Route(LlmProtocol::kUnknown, "", "/x");
  EQ_BOOL(up != nullptr, true);
  EQ_STR(up->baseUrl, "https://keep.example.com");
}

static void test_Router_empty_array_disables_routing() {
  Router& r = Router::Instance();
  EQ_BOOL(r.SetRulesFromJson("[]"), true);
  EQ_INT(r.RuleCount(), 0);
  EQ_BOOL(r.Route(LlmProtocol::kAnthropic, "glm-4.6", "/v1/messages") == nullptr,
          true);
}

// ---------- Matches 纯函数 ----------

static void test_Matches_combinations() {
  RouteRule rule;
  rule.id = "t";
  rule.modelPrefix = "glm";
  rule.protocol = "anthropic";
  rule.pathPrefix = "/v1";

  EQ_BOOL(hmsec::Matches(rule, LlmProtocol::kAnthropic, "glm-4.6", "/v1/messages"),
          true);
  EQ_BOOL(hmsec::Matches(rule, LlmProtocol::kAnthropic, "gpt-5", "/v1/messages"),
          false);  // model 前缀不中
  EQ_BOOL(hmsec::Matches(rule, LlmProtocol::kOpenAI, "glm-4.6", "/v1/messages"),
          false);  // 协议不中
  EQ_BOOL(hmsec::Matches(rule, LlmProtocol::kAnthropic, "glm-4.6", "/other"),
          false);  // 路径前缀不中

  // 全空条件 = 匹配一切
  RouteRule any;
  EQ_BOOL(hmsec::Matches(any, LlmProtocol::kUnknown, "", "/"), true);
  // protocol 为空视同 any
  EQ_BOOL(hmsec::Matches(any, LlmProtocol::kGemini, "m", "/x"), true);
}

// 用例收尾：清空规则表，避免影响同进程内靠后的其他测试（如有）
static void test_Router_cleanup() {
  EQ_BOOL(Router::Instance().SetRulesFromJson("[]"), true);
  EQ_INT(Router::Instance().RuleCount(), 0);
}

int main() {
  RUN_TEST(test_DetectProtocol_anthropic_path);
  RUN_TEST(test_DetectProtocol_openai_path);
  RUN_TEST(test_DetectProtocol_gemini_path);
  RUN_TEST(test_DetectProtocol_unknown_path_and_empty_body);
  RUN_TEST(test_DetectProtocol_body_sniff_anthropic);
  RUN_TEST(test_DetectProtocol_body_sniff_openai);
  RUN_TEST(test_DetectProtocol_body_sniff_gemini);
  RUN_TEST(test_DetectProtocol_body_no_signature);
  RUN_TEST(test_ProtocolToString);
  RUN_TEST(test_ExtractMetadata_anthropic_model_and_stream);
  RUN_TEST(test_ExtractMetadata_openai_default_stream_false);
  RUN_TEST(test_ExtractMetadata_stream_options_not_stream);
  RUN_TEST(test_ExtractMetadata_gemini_uri_fallback);
  RUN_TEST(test_ExtractMetadata_missing_model);
  RUN_TEST(test_Router_model_prefix_and_fallback);
  RUN_TEST(test_Router_protocol_filter);
  RUN_TEST(test_Router_path_prefix);
  RUN_TEST(test_Router_priority_and_tie_order);
  RUN_TEST(test_Router_rule_id_out_param);
  RUN_TEST(test_Router_invalid_json_keeps_old_table);
  RUN_TEST(test_Router_empty_array_disables_routing);
  RUN_TEST(test_Matches_combinations);
  RUN_TEST(test_Router_cleanup);
  SUMMARY();
}
