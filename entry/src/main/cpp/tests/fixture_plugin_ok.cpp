// fixture_plugin_ok.cpp —— 宿主单测用的极简测试插件（ABI 版本匹配）
//
// 由 run_host_tests.sh 现场编译成 .dll，验证 PluginManager::LoadPluginFromFile
// 的完整链路（LoadLibrary → aigate_plugin_init → ABI 校验 → vtable 调用）。
// 检测规则：body 含 "evil-plugin-token" → 阻断；含 "suspicious" → 警告；否则放行。
// M4 起同时实现 detect_response：响应含 "evil-response-token" → 阻断（ResponseScanner 插件链测试用）。
#include "aigate_plugin.h"

#include <cstdio>
#include <cstring>

static int TestDetectRequest(const char* body, char* result, size_t result_size) {
  if (body && std::strstr(body, "evil-plugin-token")) {
    if (result && result_size > 0) {
      std::snprintf(result, result_size, "blocked by test plugin");
    }
    return AIGATE_DETECT_BLOCK;
  }
  if (body && std::strstr(body, "suspicious")) {
    if (result && result_size > 0) {
      std::snprintf(result, result_size, "warned by test plugin");
    }
    return AIGATE_DETECT_WARN;
  }
  return AIGATE_DETECT_PASS;
}

// M4：响应侧检测（ResponseScanner 的插件钩子链测试用）
static int TestDetectResponse(const char* body, char* result, size_t result_size) {
  if (body && std::strstr(body, "evil-response-token")) {
    if (result && result_size > 0) {
      std::snprintf(result, result_size, "blocked by test plugin (response)");
    }
    return AIGATE_DETECT_BLOCK;
  }
  return AIGATE_DETECT_PASS;
}

static const AigatePluginVTable kVTable = {
  TestDetectRequest,   // detect_request
  TestDetectResponse,  // detect_response（M4 接线）
  nullptr,             // transform_request（M3 留位）
  nullptr              // transform_response（M3 留位）
};

static const AigatePluginInfo kInfo = {
  AIGATE_PLUGIN_API_VERSION,
  "test-plugin-ok",
  "宿主测试插件",
  "0.1.0",
  "run_host_tests.sh 现场编译的测试插件",
  "aigate-tests",
  AIGATE_PLUGIN_SECURITY
};

extern "C" AIGATE_PLUGIN_EXPORT const AigatePluginInfo* aigate_plugin_init(
    const AigatePluginVTable** vtable_out) {
  if (vtable_out) *vtable_out = &kVTable;
  return &kInfo;
}
