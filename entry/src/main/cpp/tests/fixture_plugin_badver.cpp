// fixture_plugin_badver.cpp —— ABI 版本不匹配的测试插件
//
// 由 run_host_tests.sh 现场编译成 .dll，验证宿主侧拒绝加载
// abi_version != AIGATE_PLUGIN_API_VERSION 的插件（结构布局可能已变，
// 继续读字段就是未定义行为，必须拒载）。
#include "aigate_plugin.h"

static const AigatePluginVTable kVTable = { nullptr, nullptr, nullptr, nullptr };

static const AigatePluginInfo kInfo = {
  AIGATE_PLUGIN_API_VERSION + 1,  // 故意报一个更新的 ABI 版本
  "test-plugin-badver",
  "ABI 不匹配测试插件",
  "0.0.1",
  "应被宿主拒绝加载",
  "aigate-tests",
  AIGATE_PLUGIN_SECURITY
};

extern "C" AIGATE_PLUGIN_EXPORT const AigatePluginInfo* aigate_plugin_init(
    const AigatePluginVTable** vtable_out) {
  if (vtable_out) *vtable_out = &kVTable;
  return &kInfo;
}
