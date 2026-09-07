// test_upstream.cpp —— upstream.h 纯逻辑的宿主侧单元测试
#include "../include/proxy/upstream.h"
#include "hm_test.h"

using hmsec::ParsedUrl;

static void test_ParseUrl_https_default_port() {
  ParsedUrl p = hmsec::ParseUrl("https://open.bigmodel.cn/api/anthropic");
  EQ_BOOL(p.valid, true);
  EQ_BOOL(p.tls, true);
  EQ_STR(p.scheme, "https");
  EQ_STR(p.host, "open.bigmodel.cn");
  EQ_INT(p.port, 0);  // 未显式指定
  EQ_STR(p.path, "/api/anthropic");
  EQ_INT(hmsec::DefaultPort(p.tls), 443);
}

static void test_ParseUrl_http_explicit_port() {
  ParsedUrl p = hmsec::ParseUrl("http://127.0.0.1:9099/v1/messages");
  EQ_BOOL(p.valid, true);
  EQ_BOOL(p.tls, false);
  EQ_STR(p.host, "127.0.0.1");
  EQ_INT(p.port, 9099);
  EQ_STR(p.path, "/v1/messages");
}

static void test_ParseUrl_root_path() {
  ParsedUrl p = hmsec::ParseUrl("https://api.anthropic.com");
  EQ_BOOL(p.valid, true);
  EQ_STR(p.host, "api.anthropic.com");
  EQ_STR(p.path, "/");
}

static void test_ParseUrl_invalid() {
  EQ_BOOL(hmsec::ParseUrl("").valid, false);
  EQ_BOOL(hmsec::ParseUrl("notaurl").valid, false);
  EQ_BOOL(hmsec::ParseUrl("ftp://x.com/").valid, false);  // 仅 http/https
}

static void test_JoinUrl_basic() {
  EQ_STR(hmsec::JoinUrl("https://open.bigmodel.cn/api/anthropic", "/v1/messages"),
         "https://open.bigmodel.cn/api/anthropic/v1/messages");
}

static void test_JoinUrl_trailing_slash() {
  // base 末尾多 '/' 应被去掉，避免出现双斜杠
  EQ_STR(hmsec::JoinUrl("https://api.minimaxi.com/anthropic/", "/v1/messages"),
         "https://api.minimaxi.com/anthropic/v1/messages");
}

static void test_JoinUrl_empty_path() {
  EQ_STR(hmsec::JoinUrl("https://api.x.com/base", ""), "https://api.x.com/base");
}

static void test_JoinUrl_path_without_leading_slash() {
  EQ_STR(hmsec::JoinUrl("https://api.x.com/base", "v1/messages"),
         "https://api.x.com/base/v1/messages");
}

static void test_ResolveTarget() {
  ParsedUrl t = hmsec::ResolveTarget("https://open.bigmodel.cn/api/anthropic", "/v1/messages");
  EQ_BOOL(t.valid, true);
  EQ_BOOL(t.tls, true);
  EQ_STR(t.host, "open.bigmodel.cn");
  EQ_STR(t.path, "/api/anthropic/v1/messages");
}

static void test_IsMessagesPath() {
  EQ_BOOL(hmsec::IsMessagesPath("/v1/messages"), true);
  EQ_BOOL(hmsec::IsMessagesPath("/v1/messages?beta=true"), true);  // 带 query
  EQ_BOOL(hmsec::IsMessagesPath("/v1/messages/"), true);           // 尾斜杠
  EQ_BOOL(hmsec::IsMessagesPath("/v1/models"), false);
  EQ_BOOL(hmsec::IsMessagesPath(""), false);
}

static void test_ToLower_Trim() {
  EQ_STR(hmsec::ToLower("HeLLo"), "hello");
  EQ_STR(hmsec::Trim("  ab c  "), "ab c");
}

static void test_IsAuthHeaderName() {
  EQ_BOOL(hmsec::IsAuthHeaderName("Authorization"), true);
  EQ_BOOL(hmsec::IsAuthHeaderName("authorization"), true);   // 大小写不敏感
  EQ_BOOL(hmsec::IsAuthHeaderName("X-API-Key"), true);
  EQ_BOOL(hmsec::IsAuthHeaderName("x-goog-api-key"), true);
  EQ_BOOL(hmsec::IsAuthHeaderName("proxy-authorization"), true);
  EQ_BOOL(hmsec::IsAuthHeaderName("Content-Type"), false);
  EQ_BOOL(hmsec::IsAuthHeaderName("User-Agent"), false);
}

static void test_BuildAuthHeader_anthropic_api_key() {
  // 官方 Anthropic：x-api-key
  EQ_STR(hmsec::BuildAuthHeader("ANTHROPIC_API_KEY", "sk-ant-abc"),
         "x-api-key: sk-ant-abc\r\n");
}

static void test_BuildAuthHeader_auth_token_bearer() {
  // 第三方 Claude 兼容厂商（GLM/MiniMax 等）：Bearer
  EQ_STR(hmsec::BuildAuthHeader("ANTHROPIC_AUTH_TOKEN", "glm.token123"),
         "Authorization: Bearer glm.token123\r\n");
}

static void test_BuildAuthHeader_gemini() {
  EQ_STR(hmsec::BuildAuthHeader("GEMINI_API_KEY", "AIzaXYZ"),
         "x-goog-api-key: AIzaXYZ\r\n");
}

static void test_BuildAuthHeader_empty_or_unknown() {
  EQ_STR(hmsec::BuildAuthHeader("ANTHROPIC_AUTH_TOKEN", ""), "");   // 无 Key
  EQ_STR(hmsec::BuildAuthHeader("ANTHROPIC_AUTH_TOKEN", "   "), ""); // 纯空白
  EQ_STR(hmsec::BuildAuthHeader("UNKNOWN_FIELD", "abc"), "");        // 未知字段
}

int main() {
  RUN_TEST(test_ParseUrl_https_default_port);
  RUN_TEST(test_ParseUrl_http_explicit_port);
  RUN_TEST(test_ParseUrl_root_path);
  RUN_TEST(test_ParseUrl_invalid);
  RUN_TEST(test_JoinUrl_basic);
  RUN_TEST(test_JoinUrl_trailing_slash);
  RUN_TEST(test_JoinUrl_empty_path);
  RUN_TEST(test_JoinUrl_path_without_leading_slash);
  RUN_TEST(test_ResolveTarget);
  RUN_TEST(test_IsMessagesPath);
  RUN_TEST(test_ToLower_Trim);
  RUN_TEST(test_IsAuthHeaderName);
  RUN_TEST(test_BuildAuthHeader_anthropic_api_key);
  RUN_TEST(test_BuildAuthHeader_auth_token_bearer);
  RUN_TEST(test_BuildAuthHeader_gemini);
  RUN_TEST(test_BuildAuthHeader_empty_or_unknown);
  SUMMARY();
}
