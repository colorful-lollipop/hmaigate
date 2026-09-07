// test_response_scanner.cpp —— ResponseScanner（M4 响应流式安全扫描）的宿主侧单元测试
//
// 覆盖：SSE 事件边界切分（\r\n 变体、跨 chunk 事件）、完整事件即放行、命中阻断
//（内置规则 + 文件插件 detect_response 链）、非 SSE 聚合、超上限 fail-open、Flush 尾部。
//
// 用法：test_response_scanner.exe <fixture_dll 所在目录>（由 run_host_tests.sh 传入 OUT_DIR）
#include "../include/security/response_scanner.h"
#include "../include/plugin_manager.h"
#include "hm_test.h"
#include "test_util.h"  // g_outDir / RequireOutDir（与 test_plugin 共享）

using hmsec::ResponseScanner;
using hmsec::ScanOutcome;

// SSE 响应头（content-type: text/event-stream）
static const char* kSseHeaders =
    "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n\r\n";

// ---------- SSE 边界切分与放行 ----------

static void test_sse_complete_events_pass_immediately() {
  ResponseScanner sc;
  std::string body = std::string(kSseHeaders) + "data: {\"a\":1}\n\ndata: {\"b\":2}\n\n";
  ScanOutcome out = sc.Feed(body.data(), body.size());
  EQ_BOOL(out.blocked, false);
  // 头块 + 两个完整事件一次放行
  EQ_STR(out.release, body);
  EQ_STR(sc.Flush().release, "");
}

static void test_sse_event_split_across_chunks() {
  ResponseScanner sc;
  // 头块自成第一个"事件"（\r\n\r\n 结尾），不完整 data 事件留在缓冲区
  std::string c1 = std::string(kSseHeaders) + "data: {\"a\":";
  ScanOutcome o1 = sc.Feed(c1.data(), c1.size());
  EQ_BOOL(o1.blocked, false);
  EQ_STR(o1.release, kSseHeaders);  // 头块放行，半个事件不放行

  std::string c2 = "1}\n\nda";  // 补完第一个事件 + 第二个事件开头
  ScanOutcome o2 = sc.Feed(c2.data(), c2.size());
  EQ_BOOL(o2.blocked, false);
  EQ_STR(o2.release, "data: {\"a\":1}\n\n");

  std::string c3 = "ta: {\"b\":2}\n\n";
  ScanOutcome o3 = sc.Feed(c3.data(), c3.size());
  EQ_BOOL(o3.blocked, false);
  EQ_STR(o3.release, "data: {\"b\":2}\n\n");
  EQ_STR(sc.Flush().release, "");
}

static void test_sse_crlf_event_boundary() {
  // \r\n\r\n 作为事件边界（部分上游用这种风格）
  ResponseScanner sc;
  std::string body = std::string(kSseHeaders) + "data: one\r\n\r\ndata: two\r\n\r\n";
  ScanOutcome out = sc.Feed(body.data(), body.size());
  EQ_BOOL(out.blocked, false);
  EQ_STR(out.release, body);
}

static void test_sse_incomplete_tail_flushed() {
  ResponseScanner sc;
  std::string body = std::string(kSseHeaders) + "data: tail-no-boundary";
  ScanOutcome o1 = sc.Feed(body.data(), body.size());
  EQ_STR(o1.release, kSseHeaders);  // 不完整尾部压住不放
  ScanOutcome o2 = sc.Flush();      // 收尾时扫描放行
  EQ_BOOL(o2.blocked, false);
  EQ_STR(o2.release, "data: tail-no-boundary");
}

// ---------- 命中阻断 ----------

static void test_sse_malicious_tool_use_blocked() {
  ResponseScanner sc;
  std::string body = std::string(kSseHeaders) +
      "data: {\"content\":[{\"type\":\"tool_use\",\"name\":\"bash\",\"input\":{}}]}\n\n";
  ScanOutcome out = sc.Feed(body.data(), body.size());
  EQ_BOOL(out.blocked, true);
  EQ_STR(out.release, kSseHeaders);  // 阻断点之前的已确认字节仍放行
  EQ_BOOL(out.reason.find("bash") != std::string::npos, true);
  // 阻断后的后续 Feed 不再放行
  std::string more = "data: more\n\n";
  ScanOutcome o2 = sc.Feed(more.data(), more.size());
  EQ_BOOL(o2.blocked, true);
  EQ_STR(o2.release, "");
}

static void test_sse_password_leak_blocked() {
  ResponseScanner sc;
  std::string body = std::string(kSseHeaders) + "data: password=hunter2\n\n";
  ScanOutcome out = sc.Feed(body.data(), body.size());
  EQ_BOOL(out.blocked, true);
  EQ_STR(out.release, kSseHeaders);
}

static void test_sse_safe_then_blocked_keeps_prefix() {
  // 同一 Feed 里先有安全事件、后有恶意事件：安全前缀照常放行
  ResponseScanner sc;
  std::string body = std::string(kSseHeaders) +
      "data: ok\n\n" +
      "data: {\"name\":\"powershell\"}\n\n";
  ScanOutcome out = sc.Feed(body.data(), body.size());
  EQ_BOOL(out.blocked, true);
  EQ_STR(out.release, std::string(kSseHeaders) + "data: ok\n\n");
}

// ---------- 非 SSE 聚合 ----------

static void test_non_sse_aggregates_until_flush() {
  ResponseScanner sc;
  std::string body = "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n\r\n"
                     "{\"foo\":\"bar\",\"n\":42}";
  ScanOutcome o1 = sc.Feed(body.data(), body.size());
  EQ_BOOL(o1.blocked, false);
  // 头块（有 \r\n\r\n 边界）放行；JSON body 无事件边界 → 聚合到 Flush
  EQ_STR(o1.release, "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n\r\n");
  ScanOutcome o2 = sc.Flush();
  EQ_BOOL(o2.blocked, false);
  EQ_STR(o2.release, "{\"foo\":\"bar\",\"n\":42}");
}

static void test_non_sse_malicious_body_blocked_at_flush() {
  ResponseScanner sc;
  std::string body = "HTTP/1.1 200 OK\r\n\r\n{\"name\":\"cmd\",\"args\":[]}";
  sc.Feed(body.data(), body.size());
  ScanOutcome out = sc.Flush();
  EQ_BOOL(out.blocked, true);  // "cmd" 是危险工具
  EQ_STR(out.release, "");
}

// ---------- 超上限 fail-open ----------

static void test_overflow_fail_open() {
  ResponseScanner sc(64);  // 小上限便于测试
  std::string big(100, 'x');  // 无事件边界
  ScanOutcome o1 = sc.Feed(big.data(), big.size());
  EQ_BOOL(o1.blocked, false);
  EQ_BOOL(o1.overflow, true);        // fail-open 标志
  EQ_STR(o1.release, big);           // 未扫部分放行
  // 之后本连接退化为直通，不再缓冲
  std::string more = "data: anything\n\n";
  ScanOutcome o2 = sc.Feed(more.data(), more.size());
  EQ_BOOL(o2.overflow, false);       // 只置位一次
  EQ_STR(o2.release, more);
}

// ---------- 门控 ----------

static void test_builtin_disabled_passes_everything() {
  auto& pm = aigate::PluginManager::GetInstance();
  EQ_BOOL(pm.SetPluginEnabled(aigate::kBuiltinSecurityPluginId, false), true);
  ResponseScanner sc;
  std::string body = std::string(kSseHeaders) + "data: password=hunter2\n\n";
  ScanOutcome out = sc.Feed(body.data(), body.size());
  EQ_BOOL(out.blocked, false);  // 内置检测器被插件开关禁用 → 直通
  EQ_STR(out.release, body);
  EQ_BOOL(pm.SetPluginEnabled(aigate::kBuiltinSecurityPluginId, true), true);  // 恢复
}

// ---------- M2 插件的 detect_response 链 ----------

static void test_file_plugin_response_hook_blocks() {
  auto& pm = aigate::PluginManager::GetInstance();
  EQ_BOOL(pm.LoadPluginFromFile(g_outDir + "/fixture_plugin_ok.dll"), true);
  EQ_BOOL(pm.GetEnabledResponseHooks().empty(), false);

  ResponseScanner sc;
  std::string body = std::string(kSseHeaders) + "data: evil-response-token\n\n";
  ScanOutcome out = sc.Feed(body.data(), body.size());
  EQ_BOOL(out.blocked, true);
  EQ_STR(out.reason, "blocked by test plugin (response)");
}

int main(int argc, char** argv) {
  if (!RequireOutDir(argc, argv, "test_response_scanner.exe <fixture_dll_dir>")) {
    return 1;
  }

  RUN_TEST(test_sse_complete_events_pass_immediately);
  RUN_TEST(test_sse_event_split_across_chunks);
  RUN_TEST(test_sse_crlf_event_boundary);
  RUN_TEST(test_sse_incomplete_tail_flushed);
  RUN_TEST(test_sse_malicious_tool_use_blocked);
  RUN_TEST(test_sse_password_leak_blocked);
  RUN_TEST(test_sse_safe_then_blocked_keeps_prefix);
  RUN_TEST(test_non_sse_aggregates_until_flush);
  RUN_TEST(test_non_sse_malicious_body_blocked_at_flush);
  RUN_TEST(test_overflow_fail_open);
  RUN_TEST(test_builtin_disabled_passes_everything);
  RUN_TEST(test_file_plugin_response_hook_blocks);
  SUMMARY();
}
