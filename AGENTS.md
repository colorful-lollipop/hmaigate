# AGENTS.md — AIGate（鸿蒙大模型 Agent 网关）

> 本文件面向 AI 编码代理，假设读者对本项目一无所知。项目文档与代码注释以中文为主。
> `CLAUDE.md` 已并入本文件，现仅作为指向本文件的薄壳存在——**所有指南只维护这一份**。
> 本文件只保留**最小必读**；架构细节、平台踩坑、UI 规范见文末「深读索引」，改到相关代码时按需查阅。

## 项目概述

AIGate 是一个运行在 **HarmonyOS `2in1`（PC）设备**上的本地 LLM API 转发网关：

- Agent 工具（Claude Code、Codex、Gemini CLI 等）指向 `http://127.0.0.1:<port>`；
- 网关把请求转发到用户在应用内配置的上游 LLM 供应商，并在**服务端注入真实 API Key**——密钥只存于应用偏好（ArkData preferences），从不写入 Agent 自身配置；
- 转发前 C++ 安全检测器筛查请求体（命中 BLOCK 级返回 403；请求侧密码泄露是异步审计不阻断）；响应侧由 ResponseScanner 流式扫描 SSE 事件；
- 支持系统托盘常驻（关闭窗口转隐藏 `hideAbility`）、SSE 流式透传。

**阶段状态**：网关本身 Agent 无关（C++ 侧只认 `baseUrl`/`apiKey`/`apiKeyField`/`model`）。UI 已开放三渠道（Claude Code / Codex / OpenCode），主页有渠道切换条（`CHANNEL_APPS`，见 `types/App.ets`）；**端口策略为单端口 + 活动渠道切换**（同一时刻只有一个渠道的供应商生效，每 Agent 多端口的方案已否决）。多 Agent 脚手架保留（`AppId` 枚举、per-app `ProviderRepository`、`config/` 预设、`envKeysForApp(app)`）。UI/供应商模型移植自 [cc-switch](https://github.com/farion1231/cc-switch)。

## 技术栈

| 层 | 技术 |
| --- | --- |
| UI | ArkTS / ArkUI（Stage 模型，`@State` 状态管理） |
| 核心 | C++17，经 NAPI 桥接为 `libentry.so`（模块名 `"entry"`） |
| 网络 | vendored **cpp-httplib 0.54.1**（单头库；TLS 后端 `CPPHTTPLIB_MBEDTLS_SUPPORT`） |
| TLS | vendored **mbedTLS 3.6**（静态库；**勿用 4.x**，原因见 `docs/ARCHITECTURE.md`） |
| 持久化 | `@kit.ArkData` preferences（配置唯一数据源） |
| 构建 | hvigor + ohpm，C++ 用 BiSheng 编译器，ABI `arm64-v8a` + `x86_64` |

## 构建 / 运行 / 测试命令

在仓库根目录（本机 Windows + Git Bash）执行。`hvigorw`、`node`、MinGW `g++`、`hdc` 需在 PATH；`DEVECO_SDK_HOME` 指向 DevEco SDK。

```bash
ohpm install   # 同步依赖

# 构建 HAP（C++ 走 BiSheng）
DEVECO_SDK_HOME="D:/Program Files/Huawei/DevEco Studio/sdk" \
  hvigorw --mode module -p product=default assembleHap \
  --analyze=normal --parallel --incremental --no-daemon
# 产物：entry/build/default/outputs/default/entry-default-unsigned.hap（未签名，可直接装模拟器）

# 安装 / 启动（路径必须用相对路径；hdc 会把 POSIX /e/... 路径搞坏）
hdc install -r entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell "aa start -a EntryAbility -b com.huawei.myapplication"

# C++ 宿主侧单元测试（无需设备，真正的测试覆盖在这里）
bash entry/src/main/cpp/tests/run_host_tests.sh
```

- 宿主测试用 MinGW `g++ -std=c++17` 只覆盖纯逻辑（upstream/pipeline/router/protocol/security/response_scanner/plugin/password_leak_audit），不覆盖 httplib 事件层/NAPI；当前 **307 个用例全部通过**。`run_host_tests.sh` 为表驱动（新增测试只加一行），框架是 `tests/hm_test.h` 的极简宏，无 per-test 过滤器。
- ArkTS 测试（`entry/src/test/`、`entry/src/ohosTest/`）目前是 **stub**，不要依赖（`libentry.so` 的 mock 在 `entry/src/mock/`）。原生崩溃符号化用 SDK 的 `llvm-addr2line.exe` 对未 strip 的 `entry/build/default/intermediates/cmake/default/obj/<abi>/libentry.so`。

## 关键约定（改代码前必读）

- **注释/文档用中文**；C++ 注释解释"为什么"。
- **供应商配置以 JSON 字符串**（`settingsConfigJson`）携带：`{"env":{"ANTHROPIC_BASE_URL":...,"ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY":...,"ANTHROPIC_MODEL":...}}`。
- **ArkTS 严格模式约束**（改 `.ets` 必读）：
  - 不给 `Record`/索引签名类型写对象字面量（显式 interface 可以）；空 `{}` 可以。
  - 禁用 `delete` 运算符（重建 Record）；接口字段禁用索引访问（用点访问）。
  - 带连字符的字段名转 camelCase（AppId **值**仍是 `'claude-desktop'`）；每个数据对象都要有 interface。
  - 动态 JSON 以**字符串**拼接（统一入口 `types/Json.ets`），不要 `JSON.stringify` 字面量。
  - 不允许悬浮 Promise：要么 `await`，要么 `.then(()=>{}, ()=>{})`。
  - 改 `.ets` 时用项目技能：`arkts-code-check` / `ets-lsp-check`（语言合规 + IDE 级诊断）、`arkui-codegen`（UI 约束）。
- **hilog**（两侧通用）：格式参数必须 `%{public}s`/`%{public}d`，裸 `%s` 会被掩码。C++ 用宏 `PROXY_LOG`（tag `ProxyEv`）；ArkTS 用 `@kit.PerformanceAnalysisKit`。调试：`hdc shell "hilog -x" | grep <TAG>`。
- **改 NAPI 桥接层必须同步** `entry/src/main/cpp/types/libentry/Index.d.ts` + `Types.d.ts`。
- **Ability→页面传数据**走 `AppStorage.setOrCreate` + `@StorageLink`（Ability 无法直接碰页面 `@State`）。
- **数据流单向**：`UI(Index) → GatewayController → {repository, services} → libentry.so`。controller 是唯一组合这些件的地方，视图不直接触碰 service/repository。
- **UI 设计规范**（圆角/字号/动效，不用渐变）与**平台踩坑**（picker/托盘/换肤等）见 `docs/UI-GUIDELINES.md` 与 `docs/PITFALLS.md`，改到相关代码时先查阅。

## 代码组织（速览）

### C++ 核心 `entry/src/main/cpp/`

- **两个命名空间不要混淆**：`hmsec` = 真实实现（`ProxyServer` httplib 转发代理、`request_pipeline` 转发管线、`upstream` URL/鉴权、`router` 规则路由表、`protocol_adapter` 多协议识别、`security_detector` 规则引擎、`response_scanner` 响应流式扫描、`password_leak_audit` 异步审计、`plugin` 动态库插件机制）；`aigate` = 旧门面层（`ProxyEngine` 薄壳委托给 `hmsec::ProxyServer::Instance()`；**例外：`SecurityDetector` 是真实现**）。
- **转发管线**（`request_pipeline.*`，纯逻辑、宿主可测）三步：`ResolveRoute`（协议识别 + Router 规则表，未命中回退默认上游）→ `SecurityCheckRequest`（只查请求体，只阻断 BLOCK 级命中）→ `BuildRequest`（重写 Host、剔 hop-by-hop/客户端鉴权头、注入网关 Key）。
- `napi/napi_proxy.cpp` — NAPI 表面 17 个函数（代理启停/状态、安全规则与自定义词条、响应检测开关、插件、路由表、密码泄露审计）；读字符串统一走 `GetStringArg`/`GetStringProp` 助手。
- 公共件：`include/json_scan.h`（手写最小 JSON 扫描器，**刻意不引 JSON 库**：大 body 性能 + 零依赖）、`include/str_util.h`（`ToLower`）。
- `third_party/`：cpp-httplib 0.54.1（MIT，单头库）+ mbedTLS 3.6（勿用 4.x；上游 TLS 为 `VERIFY_NONE`，本地可信网关场景可接受）。
- **转发主流程**、模块级细节、TLS 决策与安全检测设计：见 `docs/ARCHITECTURE.md`。

### ArkTS 层 `entry/src/main/ets/`（分层，依赖向内）

- `types/` — 共享接口唯一数据源（`ProxyTypes`/`SecurityTypes`/`PluginTypes`/`Provider`/`App`/`Preset`/`EnvKeys`/`RouteRule`/`Skin`/`Json`）。
- `repository/` — 只做持久化（preferences），无业务逻辑：`ProviderRepository`（per-app 供应商 CRUD）、`SettingsRepository`（**配置唯一数据源**：代理/安全/路由/外观/活动渠道/云端连接等）。
- `services/` — NAPI 薄封装：`ProxyService`/`SecurityService`/`PluginService`/`RouteService`；**非 NAPI**：`CloudConfigurationService`（云端拉取）、`RuleCustomService`（规则自定义词条持久化↔回放）、`LocalConfigService`（picker 管理三渠道本地配置的接管与备份恢复）、`TrayService`（托盘）、`PasswordLeakAuditService`。
- `app/GatewayController.ets` — 编排/用例层：渠道切换、供应商 CRUD、代理启停、路由规则、云端预设入口；初始化/供应商变更/启动/切换时推送上游与路由表，**运行中也能热更新**；codex upstream 从 `{auth, config(TOML)}` 解析，`cppApiKeyField` 把 `OPENAI_API_KEY` 映射为 `ANTHROPIC_AUTH_TOKEN`（C++ 零改动）。`app/ThemeController.ets` — 亮暗切换与皮肤强调色（走 AppStorage）。
- `pages/Index.ets` — 唯一页面，纯视图；`components/` — `settings/` 各设置分区、`provider/`、`common/`（DialogShell 等）、`ConfigPanel`（壳）；`config/` — 预设供应商模板。

## 安全注意事项

- 真实 API Key 只存 preferences，永不落盘到 Agent 配置（写入本地配置的都是 `aigate-proxy` 占位 token）。
- **安全检测只查 body，不查头**（避免合法 `Bearer`/`x-api-key` 被误判）——不要"顺手"把 header 加进去；响应侧跳过 `HTTP/` 头块同理。
- **请求侧 `password_leak` 不阻断**，走 `PasswordLeakAudit` 异步审计（有界队列，只存脱敏元数据，绝无原文/密钥片段；保留 200 条 / 30 天）；响应侧保留同步阻断。
- `doc/settings.json` 含真实密钥，已 gitignore，**切勿提交或外发**；`build-profile.json5` 内含本机签名材料路径，不要外发。
- lint 启用 `@security/*` 规则（禁不安全 AES/hash/RSA 等），新代码不要触发。

## 关键配置文件

- `oh-package.json5`（根/entry）、`build-profile.json5`（根：targetSdkVersion 6.1.1(24)、BiSheng；**签名配置为空**，在 DevEco 里自动生成）、`entry/build-profile.json5`（指向 CMakeLists）、`AppScope/app.json5`（bundleName `com.huawei.myapplication`）、`entry/src/main/module.json5`（`deviceTypes: ["2in1"]`、权限、`supportWindowMode` 含 floating）、`entry/src/main/cpp/CMakeLists.txt`（httplib 以 `httplib/httplib.h` 形式包含，`CPPHTTPLIB_MBEDTLS_SUPPORT` 定义在 target 上）。
- `local.properties` gitignore 自动生成勿改；`code-linter.json5`（ArkTS lint）；`.clangd`/`.clang-tidy`（C++ 检查）。
- `LICENSE`/`NOTICE`（MIT）、`CONTRIBUTING.md`、`README_EN.md`、`.github/workflows/ci.yml`（windows-latest 跑宿主测试）。

## 文档可信度

`README.md` / `docs/*` 已重写为与实现一致，可以信任。若文档与源码冲突，**以源码和本文件为准**。

## 项目技能（`.agents/skills/`）

`arkts-code-check`（ArkTS 合规审查）、`ets-lsp-check`（LSP 级诊断）、`arkui-codegen`（ArkUI 约束）、`arkts-code-lookup`（API 查询）、`harmony-build` / `harmony-fix`（构建与错误修复，注意其路径是 macOS 风格，Windows 直接调 `hvigorw`）、`snapshot`（设备截图）、`huawei-docs-scraper`。

> **注意**：`.agents/` 是本机 AI 工具链（含抓取的华为文档，体积大），**不随仓库分发**（已 gitignore）。开源仓库使用者无需关心本节。

## 深读索引（按需查阅，不必常驻上下文）

| 场景 | 文档 |
| --- | --- |
| C++ 架构细节、转发主流程、TLS 决策、安全检测/插件/云端/picker 设计 | `docs/ARCHITECTURE.md` |
| 环境、构建产物、目录树、添加预设/规则/管线步骤的操作指南 | `docs/DEVELOPMENT.md` |
| **平台踩坑**：httplib/streaming、regex 中文、picker/沙箱文件、URI 持久化、沉浸式标题栏、托盘常驻、Toggle 宽度、HAP 错误码、换肤 | `docs/PITFALLS.md` |
| **UI 设计规范**：不用渐变、圆角/字号层级、交互动效、@Builder 传参坑 | `docs/UI-GUIDELINES.md` |
| 项目背景与设计动机 | `docs/BACKGROUND.md` |
