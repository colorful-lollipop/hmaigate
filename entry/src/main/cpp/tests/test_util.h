// test_util.h —— 需要 fixture 插件目录的测试共享的辅助（R2 从 test_plugin.cpp 抽出）
//
// 用法：main 开头调 RequireOutDir(argc, argv)（由 run_host_tests.sh 传入 OUT_DIR）。
#pragma once

#include <cstdio>
#include <string>
#include <vector>

#include "../include/plugin_manager.h"

// fixture .dll 所在目录（argv[1]）
inline std::string g_outDir;

// 解析并校验 OUT_DIR 入参；缺失打印 usage 并返回 false（main 直接 return 1）
inline bool RequireOutDir(int argc, char** argv, const char* usage) {
  if (argc < 2) {
    printf("usage: %s\n", usage);
    return false;
  }
  g_outDir = argv[1];
  return true;
}

// 在插件表快照里按 id 找记录（找不到返回 nullptr）
inline const aigate::PluginRecord* FindById(const std::vector<aigate::PluginRecord>& list,
                                            const std::string& id) {
  for (const auto& p : list) {
    if (p.id == id) return &p;
  }
  return nullptr;
}
