#!/usr/bin/env bash
# run_host_tests.sh —— 宿主侧（MinGW g++）编译并运行 C++ 纯逻辑单元测试
#
# 这些测试不依赖网络库 / 鸿蒙 NAPI，只覆盖可纯函数化的逻辑
#（URL 解析、鉴权头构造、安全检测规则、协议识别、规则路由、插件加载、响应扫描），
# 便于在提交前快速回归。
#
# 表驱动（R2）：新增测试只需在 TESTS 数组加一行：名字|源文件依赖|[outdir]。
# 第三段为 "outdir" 时，运行阶段传入 OUT_DIR（fixture .dll 所在目录）。
#
# 用法：  bash entry/src/main/cpp/tests/run_host_tests.sh
set -euo pipefail

CPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$CPP_DIR/tests"
OUT_DIR="$TEST_DIR/.out"
mkdir -p "$OUT_DIR"

CXX="${CXX:-g++}"
CXXFLAGS="-std=c++17 -Wall -Wextra -O0 -g -I$CPP_DIR -I$CPP_DIR/include"

FAIL=0

# M2/M4 插件测试依赖的 fixture：先现场编译（-static-libgcc/-static-libstdc++ 让
# fixture 自带运行时，LoadLibraryA 时不依赖 PATH 里的 MinGW 运行时 dll）。
echo "== building test plugin fixtures =="
"$CXX" $CXXFLAGS -shared -static-libgcc -static-libstdc++ \
  "$TEST_DIR/fixture_plugin_ok.cpp" \
  -o "$OUT_DIR/fixture_plugin_ok.dll" || FAIL=1
"$CXX" $CXXFLAGS -shared -static-libgcc -static-libstdc++ \
  "$TEST_DIR/fixture_plugin_badver.cpp" \
  -o "$OUT_DIR/fixture_plugin_badver.dll" || FAIL=1

# 名字|实现源文件（空格分隔，相对 cpp 根）|运行参数（outdir=传 OUT_DIR）
TESTS=(
  "test_upstream|core/proxy/upstream.cpp|"
  "test_security|core/security/security_detector.cpp|"
  "test_request_pipeline|core/proxy/upstream.cpp core/proxy/request_pipeline.cpp core/proxy/router.cpp core/protocol/protocol_adapter.cpp core/security/security_detector.cpp core/security/password_leak_audit.cpp core/plugin/plugin_manager.cpp|"
  "test_protocol|core/protocol/protocol_adapter.cpp core/proxy/router.cpp|"
  "test_plugin|core/security/security_detector.cpp core/security/password_leak_audit.cpp core/plugin/plugin_manager.cpp|outdir"
  "test_response_scanner|core/security/security_detector.cpp core/security/password_leak_audit.cpp core/security/response_scanner.cpp core/plugin/plugin_manager.cpp|outdir"
  "test_password_leak_audit|core/security/password_leak_audit.cpp|"
)

# 编译阶段：全部编完再跑，编译错误一次看全
for entry in "${TESTS[@]}"; do
  IFS='|' read -r name srcs _ <<< "$entry"
  echo "== building $name =="
  src_args=()
  for src in $srcs; do
    src_args+=("$CPP_DIR/$src")
  done
  "$CXX" $CXXFLAGS "${src_args[@]}" "$TEST_DIR/$name.cpp" \
    -o "$OUT_DIR/$name.exe" || FAIL=1
done

if [ "$FAIL" -ne 0 ]; then
  echo "BUILD FAILED"
  exit 1
fi

for entry in "${TESTS[@]}"; do
  IFS='|' read -r name _ arg <<< "$entry"
  echo
  echo "== running $name =="
  if [ "$arg" = "outdir" ]; then
    "$OUT_DIR/$name.exe" "$OUT_DIR" || FAIL=1
  else
    "$OUT_DIR/$name.exe" || FAIL=1
  fi
done

echo
if [ "$FAIL" -ne 0 ]; then
  echo "❌ SOME TESTS FAILED"
  exit 1
fi
echo "✅ ALL HOST TESTS PASSED"
