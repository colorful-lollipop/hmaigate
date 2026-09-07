# AIGate 开发指南

> 上手速查文档。根目录 `AGENTS.md` 是最小必读的唯一权威入口，架构细节见
> `ARCHITECTURE.md`，平台踩坑见 `PITFALLS.md`，UI 规范见 `UI-GUIDELINES.md`。

## 环境

- Windows + Git Bash；`hvigorw`、`node`、MinGW `g++`、`hdc` 在 PATH；
- `DEVECO_SDK_HOME` 指向 DevEco SDK（如 `D:/Program Files/Huawei/DevEco Studio/sdk`）；
- 首次构建前执行 `ohpm install`；
- 签名材料不随仓库分发：在 DevEco Studio 中 File > Project Structure > Signing
  Configs 勾选自动生成即可（无签名配置时产出未签名 HAP，可直接装模拟器）。

## 构建 / 安装 / 启动

```bash
# 构建 HAP（C++ 走 BiSheng）
DEVECO_SDK_HOME="D:/Program Files/Huawei/DevEco Studio/sdk" \
  hvigorw --mode module -p product=default assembleHap \
  --analyze=normal --parallel --incremental --no-daemon
# 产物：entry/build/default/outputs/default/entry-default-unsigned.hap

# 安装 / 启动（路径必须用相对路径；hdc 会把 POSIX /e/... 路径搞坏）
hdc install -r entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell "aa start -a EntryAbility -b com.huawei.myapplication"
```

常见安装错误：`9568297`（SDK 太新）、`9568332`（签名不一致，先
`hdc uninstall com.huawei.myapplication` 再装，`-r` 只在签名一致时有效）。

## 测试

```bash
# C++ 宿主侧单元测试（无需设备，真正的测试覆盖在这里）
bash entry/src/main/cpp/tests/run_host_tests.sh
```

- 用 MinGW `g++ -std=c++17` 编译 `upstream.cpp` / `request_pipeline.cpp` /
  `router.cpp` / `protocol_adapter.cpp` / `security_detector.cpp` /
  `response_scanner.cpp` / `plugin_manager.cpp` / `password_leak_audit.cpp` 及对应
  测试到 `tests/.out/`（已 gitignore），只覆盖纯逻辑，不覆盖 httplib 事件层/NAPI。
- `run_host_tests.sh` 是表驱动（TESTS 数组：名字|源文件依赖|运行参数，新增测试只
  加一行）；插件测试会把 `fixture_plugin_ok/badver.cpp` 现场编译成 `.dll` 走真实
  `LoadLibrary` 链路。
- 测试框架是 `tests/hm_test.h` 的极简宏（`EQ_STR`/`EQ_BOOL`/`EQ_INT`、`RUN_TEST`、
  `SUMMARY`），无 per-test 过滤器；跑单个测试需注释掉其他 `RUN_TEST` 行。插件测试
  共享助手在 `tests/test_util.h`。
- ArkTS 测试（`entry/src/test/`、`entry/src/ohosTest/`）目前是 stub，不要依赖；
  `libentry.so` 的 mock 在 `entry/src/mock/`。
- 原生崩溃符号化：用 DevEco SDK 的 `llvm-addr2line.exe` 对未 strip 的
  `entry/build/default/intermediates/cmake/default/obj/<abi>/libentry.so`。
- CI（`.github/workflows/ci.yml`）在 windows-latest 上跑同一份宿主测试脚本。

## 目录结构速览

```
aigate/
├── AppScope/                  # 应用级配置（bundleName 等）
├── entry/
│   └── src/main/
│       ├── cpp/               # C++ 核心（libentry.so）
│       │   ├── core/
│       │   │   ├── proxy/     # proxy_server（httplib 转发）+ request_pipeline + upstream + router
│       │   │   ├── protocol/  # 多协议识别（anthropic/openai/gemini）
│       │   │   ├── security/  # security_detector + response_scanner + password_leak_audit
│       │   │   └── plugin/    # 插件机制（纯 C ABI 动态库加载 + 内置适配器）
│       │   ├── napi/          # NAPI 桥接（模块名 "entry"）
│       │   ├── include/       # 头文件 + json_scan.h/str_util.h 公共件
│       │   ├── third_party/   # cpp-httplib 0.54.1 + mbedTLS 3.6（vendored）
│       │   ├── types/libentry/# NAPI 的 TS 类型声明（改桥接层必须同步）
│       │   └── tests/         # 宿主单测 + run_host_tests.sh（表驱动）
│       ├── ets/               # ArkTS 层
│       │   ├── types/         # 共享接口唯一数据源
│       │   ├── repository/    # preferences 持久化（无业务逻辑）
│       │   ├── services/      # NAPI 薄封装 + Cloud/LocalConfig/RuleCustom/Tray
│       │   ├── app/           # GatewayController（编排层）+ ThemeController
│       │   ├── pages/         # Index.ets（唯一页面，纯视图）
│       │   ├── components/    # UI 组件（settings/ 各分区、provider/、common/）
│       │   └── config/        # 预设供应商模板
│       ├── module.json5       # deviceTypes: ["2in1"]、权限、窗口模式
│       └── resources/
├── cloud/                     # 云端控制面（可选）：Spring Boot 后端 + React 控制台
├── docs/                      # 架构文档 / 开发指南 / 项目背景
└── AGENTS.md                  # 唯一权威事实来源
```

## 编码约定摘要

- 注释/文档用中文；C++ 注释解释"为什么"（见 `CMakeLists.txt` 风格）。
- **ArkTS 严格模式**：不给 `Record`/索引签名类型写对象字面量（显式 interface 可以，
  空 `{}` 可以）；禁用 `delete` 运算符；接口字段禁用索引访问；带连字符的字段名转
  camelCase；每个数据对象都要有 interface；动态 JSON 以字符串拼接；不允许悬浮
  Promise（`await` 或 `.then(()=>{}, ()=>{})`）。
- hilog：C++ 用 `PROXY_LOG`（tag `ProxyEv`）；ArkTS 用 `@kit.PerformanceAnalysisKit`
  的 `hilog`。格式参数必须 `%{public}s`/`%{public}d`，裸 `%s` 会被掩码为 `<private>`。
  调试：`hdc shell "hilog -x" | grep <TAG>`。
- 改 NAPI 桥接层必须同步 `types/libentry/Index.d.ts` + `Types.d.ts`。
- UI 设计规范（圆角/字号层级/动效/换肤走 AppStorage）见 `UI-GUIDELINES.md`，
  平台踩坑速查见 `PITFALLS.md`。

## 如何添加预设供应商

1. 在 `entry/src/main/ets/config/` 下参照现有 Claude/Codex/Gemini/OpenCode 预设
   新建预设文件；
2. 在 `PresetRegistry` 里注册；
3. 若涉及新的 env 键集合，更新 `types/EnvKeys.ets` 的 `envKeysForApp(app)`
   （返回 `EnvKeySet{baseUrlKey, modelKey, apiKeyField}`）；
4. 供应商 env JSON 通过 `GatewayController.providerToUpstream(app, provider)` 转成
   `UpstreamConfig` 推给 C++ 侧，C++ 已接受任意 `apiKeyField`，一般无需改原生代码。

## 如何添加安全检测规则

1. 在 `entry/src/main/cpp/core/security/security_detector.{cpp,h}` 添加规则
   （参照现有四条默认规则；自定义词条/命中计数由 `DetectionRule` 基类提供）；
2. 在 `entry/src/main/cpp/tests/test_security.cpp` 补宿主单测；
3. 规则如需暴露开关给 UI，同步 `SecurityService`（ArkTS）与 NAPI 类型声明
   （`types/libentry/Index.d.ts` + `Types.d.ts`）。

## 如何修改转发管线

管线三步骤（`request_pipeline.*`）均为无网络库依赖的纯函数，改任一步骤须在
`tests/test_request_pipeline.cpp` 补宿主单测；涉及协议识别改 `protocol_adapter.*`
（配套 `test_protocol.cpp`），涉及路由改 `router.*`（配套 `test_router.cpp`）。

## 云端控制面（可选）

`cloud/` 下是独立的可选组件（Spring Boot + SQLite 后端、React 控制台、Docker 部署），
设备端默认不依赖它。开发与部署见 `cloud/README.md` 与 `cloud/docs/`。
