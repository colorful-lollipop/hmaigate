# AGENTS.md — AIGate（鸿蒙大模型 Agent 网关）

> 本文件面向 AI 编码代理，假设读者对本项目一无所知。项目文档与代码注释以中文为主。
> `CLAUDE.md` 已并入本文件，现仅作为指向本文件的薄壳存在——**所有指南只维护这一份**。

## 项目概述

AIGate 是一个运行在 **HarmonyOS `2in1`（PC）设备**上的本地 LLM API 转发网关：

- Agent 工具（Claude Code、Codex、Gemini CLI 等）指向 `http://127.0.0.1:<port>`；
- 网关把请求转发到用户在应用内配置的上游 LLM 供应商，并在**服务端注入真实 API Key**——密钥只存于应用偏好（ArkData preferences），从不写入 Agent 自身配置；
- 转发前可用 C++ 安全检测器筛查请求体（提示注入 / 上下文注入），命中返回 403；**请求侧密码泄露已改为异步审计**（password-leak-audit，转发不阻断、只生成脱敏提醒记录，见下文"安全注意事项"）；M4 起响应侧检测已接线（ResponseScanner 流式扫描 SSE 事件，恶意 tool use / 密码泄露命中 BLOCK 级即拦，见下文"转发主流程"）；
- 支持系统托盘常驻（状态栏图标 + 关闭窗口转隐藏 `hideAbility`）、SSE 流式透传。

**阶段状态**：网关本身 Agent 无关（C++ 侧只认 `baseUrl`/`apiKey`/`apiKeyField`/`model`，从不关心是哪个工具在调用）。**UI 已开放三渠道（多渠道管理）**：Claude Code / Codex / OpenCode，主页供应商区上方有渠道切换条（`CHANNEL_APPS`，见 `types/App.ets`），`GatewayController.ACTIVE_APP` 常量已改为动态 `activeAppId`（持久化在 `SettingsRepository.activeAppId`，启动回放；`setActiveApp` = 持久化 + 推该渠道当前供应商 + 重下发路由表）。**端口策略已定为单端口 + 活动渠道切换**（cc-switch 式 UX，同一时刻只有一个渠道的供应商生效）——理由：贴合 cc-switch 的交互习惯，且 C++ 侧渠道无关、零改动；每 Agent 一个端口的方案已否决。多 Agent 脚手架继续保留（`AppId` 枚举 `claude`/`codex`/`gemini`/`opencode`/…、per-app `ProviderRepository`、`config/` 预设文件、`envKeysForApp(app)`）。UI/供应商模型移植自 [cc-switch](https://github.com/farion1231/cc-switch)。

## 技术栈

| 层 | 技术 |
| --- | --- |
| UI | ArkTS / ArkUI（Stage 模型，`@State` 状态管理） |
| 核心 | C++17，经 NAPI 桥接为 `libentry.so`（模块名 `"entry"`） |
| 网络 | vendored **mongoose 7.22**（socket 路径；TLS 后端 `MG_TLS=MG_TLS_MBED`） |
| TLS | vendored **mbedTLS 3.6**（静态库；**勿用 4.x 和 mongoose 内置 TLS**，原因见下文） |
| 持久化 | `@kit.ArkData` preferences（配置唯一数据源） |
| 构建 | hvigor + ohpm，C++ 用 BiSheng 编译器，ABI `arm64-v8a` + `x86_64` |

## 关键配置文件

- `oh-package.json5`（根/entry）— ohpm 包定义；entry 以 `file:./src/main/cpp/types/libentry` 依赖 `libentry.so` 的 TS 类型。devDependencies 有 `@ohos/hypium` / `@ohos/hamock`。
- `build-profile.json5`（根）— `targetSdkVersion 6.1.1(24)`、`nativeCompiler: BiSheng`；**签名配置为空**（签名材料属本机隐私不入库，在 DevEco Studio 里自动生成即可，见 `docs/DEVELOPMENT.md`）。**历史：曾因安装错误 9568297 锁定 5.0.0(12)，现已升到 6.1.1(24)，以文件为准。**
- `entry/build-profile.json5` — `externalNativeOptions` 指向 `entry/src/main/cpp/CMakeLists.txt`，abiFilters `arm64-v8a`/`x86_64`。
- `AppScope/app.json5` — bundleName `com.huawei.myapplication`。
- `entry/src/main/module.json5` — `deviceTypes: ["2in1"]`；权限 `INTERNET`、`FILE_ACCESS_PERSIST`；`supportWindowMode: ["fullscreen","split","floating"]`（沉浸式标题栏依赖 floating 模式）。
- `entry/src/main/cpp/CMakeLists.txt` — 构建 `libentry.so`：NAPI + 代理核心 + mongoose.c + mbedtls 静态库；宏 `MG_TLS=MG_TLS_MBED`、`MG_ENABLE_LOG=0`；链接 `pthread`；`-I third_party` 使头文件以 `mongoose/mongoose.h` 形式包含（**不是**裸 `mongoose.h`）。
- `code-linter.json5` — ArkTS lint（`@performance/recommended` + `@typescript-eslint/recommended` + 一组 `@security/*` 加密规则），忽略 test/ohosTest/mock。
- `.clangd` / `.clang-tidy` — C++ 静态检查配置。
- `local.properties` — DevEco SDK 路径（已 gitignore，自动生成勿改）。
- `doc/settings.json` — **含真实 API Key，已 gitignore，切勿提交或外发**。
- `LICENSE` / `NOTICE` — GPL-2.0-only 许可证文本与 vendored 组件许可声明（mongoose 双许可 ⇒ 项目整体 GPL-2.0-only）。
- `CONTRIBUTING.md` — 中英双语贡献指南；`README_EN.md` 为 README 的英文版。
- `docs/` — `ARCHITECTURE.md`（架构）、`DEVELOPMENT.md`（开发指南）、`BACKGROUND.md`（项目背景与设计动机）、`images/`（README 引用的截图）。
- `.github/workflows/ci.yml` — CI：windows-latest 上用 MinGW g++ 跑 `run_host_tests.sh`；`.github/ISSUE_TEMPLATE/` 为中文 Issue 表单。

## 构建 / 运行 / 测试命令

在仓库根目录（本机 Windows + Git Bash）执行。`hvigorw`、`node`、MinGW `g++`、`hdc` 需在 PATH；`DEVECO_SDK_HOME` 指向 DevEco SDK。

```bash
# 同步依赖
ohpm install

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

- 宿主测试用 MinGW `g++ -std=c++17` 编译 `upstream.cpp`/`request_pipeline.cpp`/`router.cpp`/`protocol_adapter.cpp`/`security_detector.cpp`/`response_scanner.cpp`/`plugin_manager.cpp`/`password_leak_audit.cpp` 及对应测试到 `tests/.out/`（已 gitignore），只覆盖纯逻辑（URL 解析、鉴权头构造、转发管线步骤、检测规则、响应流式扫描、插件动态加载、协议识别、规则路由、密码泄露异步审计），不覆盖 mongoose/NAPI。插件测试会现场把 `fixture_plugin_ok/badver.cpp` 编译成 `.dll` 走真实 `LoadLibrary` 链路。当前状态：**46 + 40（test_security，请求侧密码泄露断言已改写为异步审计行为）+ 38 + 67（test_protocol，M3 新增）+ 43（test_plugin）+ 43（test_response_scanner，M4 新增）+ 30（test_password_leak_audit，2026-08 新增）= 307 全部通过**（2026-08-19 验证）。测试框架是 `tests/hm_test.h` 的极简宏（`EQ_STR`/`EQ_BOOL`/`EQ_INT`、`RUN_TEST`、`SUMMARY`），无 per-test 过滤器，跑单个测试需注释掉其他 `RUN_TEST` 行。R2 起 `run_host_tests.sh` 为表驱动（TESTS 数组：名字|源文件依赖|运行参数，新增测试只加一行），插件测试共享的 `g_outDir`/`FindById` 助手在 `tests/test_util.h`。
- ArkTS 测试（`entry/src/test/`、`entry/src/ohosTest/`）目前是 **stub**，不要依赖；`libentry.so` 的 mock 在 `entry/src/mock/`（mock-config 会把它映射成只有 `add` 的假模块，是 ohosTest 受阻的原因）。如要补真实用例，走 DevEco 测试运行器或 hvigor `test` 任务。
- 原生崩溃符号化：`sdk/default/openharmony/native/llvm/bin/llvm-addr2line.exe` 对未 strip 的 `entry/build/default/intermediates/cmake/default/obj/<abi>/libentry.so`。

## 代码组织

### C++ 核心 `entry/src/main/cpp/`

- **`napi/napi_proxy.cpp`** — ArkTS↔C++ 边界，注册模块 `"entry"`，暴露 17 个函数：`startProxy`/`stopProxy`/`getProxyStatus`/`setUpstream`、`getSecurityRules`/`setRuleEnabled`、`updateRuleConfig(ruleId, configJson): boolean`（M4，增删规则自定义词条，非法 JSON/未知 ruleId 返回 false）、`setResponseSecurityEnabled(enabled)`（M4，响应侧检测开关）、`loadPlugins(dir): Promise<number>` / `listPlugins(): string(JSON)` / `setPluginEnabled(id, enabled): boolean`（M2）、`setRouteRules(rulesJson): boolean`（M3——原子替换整张路由表，非法 JSON 返回 false 不动旧表，空数组 `[]` 关闭路由）、`setPasswordLeakAuditEnabled(enabled)` / `getPasswordLeakAuditStatus(): string(JSON)` / `getPasswordLeakAlerts(offset, limit): string(JSON)` / `markPasswordLeakAlertsRead(idsJson): number` / `clearPasswordLeakAlerts()`（2026-08 密码泄露提醒，只传脱敏元数据，告警正文与密钥片段不过 NAPI）。**R1 已下线 7 个 ArkTS 零调用函数**：`detectRequest`/`getConfig`/`setConfig`/`loadConfigFile`/`loadPlugin`/`unloadPlugin`/`getLoadedPlugins`（随旧 IPlugin 路径与 ConfigManager 一起删除）。**M4 起 `getSecurityRules()` 由 `string[]` 改为规则列表 JSON 字符串**（元素：`id/name/enabled/hitCount/customKeywords/customPatterns`，见 `Types.d.ts` 的 `NativeSecurityRule`）。NAPI 读字符串统一走 `GetStringArg`/`GetStringProp` 两段式助手（先取长度再分配，R2 起不再有定长 char 缓冲）。TS 类型声明在 `types/libentry/Index.d.ts` + `Types.d.ts`，**改桥接层时必须同步这两个文件**。`ProxyStatus` 的 `successRequests`/`failedRequests`/`lastError`/`responseSecurityEnabled`（M4）已端到端打通（NAPI + types），供排障用。
- **两个命名空间不要混淆**：
  - `namespace hmsec` — 真实实现。`ProxyServer`（单例）是 mongoose 事件驱动转发代理；`request_pipeline.*` 是转发管线纯逻辑（有宿主单测）；`upstream.*` 是纯 URL/鉴权逻辑（有宿主单测）。
  - `namespace aigate` — 旧门面层，持有 NAPI 表面。`ProxyEngine`（单例，`core/proxy/proxy_engine.cpp`）只是薄壳，`Impl` 把 `Start/Stop/GetStatus/SetUpstream` 委托给 `hmsec::ProxyServer::Instance()`；保留它的真实价值是 Impl 记住 Start 时的 host/port 回填 `GetStatus`（R1 已删 `RequestInterceptor`/`SetRequestInterceptor`/`UpdateConfig`/上游代理死字段等零调用成员）。**例外：`SecurityDetector` 是真实现**，由 `request_pipeline` 的 `SecurityCheckRequest` 直接调用。
- `core/proxy/proxy_server.{cpp,h}` — mongoose 事件分发 + 连接生命周期（`ConnCtx`）；`core/proxy/request_pipeline.{cpp,h}`（头文件在 `include/proxy/`）— **转发管线（M1 重构抽出）**，三个纯逻辑步骤，无 mongoose 依赖、宿主可测：`ResolveRoute`（M3 起先做协议识别 + 元数据提取，再查 `Router` 规则表——命中用规则上游，未命中/规则表为空回退默认上游；返回 `RouteResult{ok,error,upstream,target,ruleId,model,protocol}`，`RouteError` 区分 `kNoUpstream`/`kBadUpstreamUrl`；默认上游的互斥锁读取仍由调用方 `CurrentUpstream()` 完成）、`SecurityCheckRequest`（只查请求体；M2 起分两段——内置 SecurityDetector 受插件表 `builtin-security-detector` 开关门控，随后链式调用已启用文件来源 security 插件的 `detect_request`，任一返回 BLOCK(2) 即拦截；**M4 起尊重「级别→动作」映射**：只阻断映射为 BLOCK 的命中，WARN 级如 `context_injection` 只进 hitCount——为保持既有阻断行为，`password_leak`/`prompt_injection` 的默认级别同步由 CRITICAL 提升为 BLOCK）、`BuildRequest`（重写 Host、剔 hop-by-hop/客户端鉴权头、`BuildAuthHeader` 注入网关 Key，入参为 `HeaderList` 纯字符串头列表）；`core/proxy/upstream.{cpp,h}` — `BuildAuthHeader` 映射 `ANTHROPIC_API_KEY`→`x-api-key`、`ANTHROPIC_AUTH_TOKEN`→`Authorization: Bearer`、`GEMINI_API_KEY`→`x-goog-api-key`。
- `core/protocol/protocol_adapter.{cpp,h}`（头文件在 `include/protocol/`，M3 新增）— **多 LLM 协议识别**：`DetectProtocol(method, uri, body)` 按路径特征（`/v1/messages`→anthropic、`/v1/chat/completions`/`/v1/responses`→openai、`:generateContent`/`:streamGenerateContent`→gemini）+ body 字段签名兜底（`max_tokens`+`messages`/`contents`/`messages`）识别 `LlmProtocol`；`ExtractMetadata` 用手写字符串扫描提取 `model`/`stream`（**刻意不引 JSON 库**：大 body 性能 + 零依赖；gemini 的 model 从 uri `/models/<m>:` 兜底）。纯函数、宿主可单测。
- `core/proxy/router.{cpp,h}`（头文件在 `include/proxy/`，M3 新增）— **规则路由表**（`Router` 单例）：`SetRulesFromJson` 用手写最小 JSON 扫描（R2 起收敛到公共 `include/json_scan.h` 的 `hmsec::JsonCursor`；不引 JSON 库的理由见其头部注释：结构固定由 ArkTS 生成 + 大 body 性能 + 零依赖；非法返回 false 不动旧表，空数组关路由），规则表以 `shared_ptr<const vector>` 不可变快照整体 swap（热更新安全）；`Route(proto, model, uri)` 按 `(modelPrefix 前缀 && protocol && pathPrefix 前缀)` 匹配，`priority` 大者优先、同优先级按数组顺序。规则 JSON schema 见 `Types.d.ts` 的 `NativeRouteRule`。
- `core/security/security_detector.{cpp,h}` — 可插拔规则引擎，默认启用四条规则：`password_leak`(请求/响应)、`malicious_tool_use`(响应)、`prompt_injection`(请求，M4 补中文模式)、`context_injection`(M4 新增，请求；伪装系统指令/越权操纵，中英文兼有——**保守取向：默认级别 CRITICAL 映射 WARN，只记录不阻断**)。`DetectRequest`/`DetectResponse` 返回最严重的一条结果并给命中规则 `hitCount` 原子 +1。M4 起 `DetectionRule` 基类支持用户自定义词条（`AddCustomKeyword`/`RemoveCustomKeyword`/`AddCustomPattern`/`RemoveCustomPattern` + 查询，互斥锁保护；各规则检测路径在内置检查后统一 `MatchCustom` 兜底），`SecurityDetector::UpdateRuleConfig`/`UpdateRuleConfigFromJson`（JSON 扫描与 router 共用 `include/json_scan.h`；**坑：std::regex 按字节匹配，可选中文必须写 `(的)?` 分组，`的?` 永不匹配**）/`GetRuleInfos`。R2 起：`DetectionRule::MakeHit(message, pos)` 统一构造命中结果；大小写不敏感匹配统一走 `include/str_util.h` 的 `hmsec::ToLower`（原 upstream.cpp 的实现已并入）；`SecurityDetector::IsBlocking(result)` 收敛管线/响应扫描器/内置适配器三处「!isSafe && 动作映射==BLOCK」判断。
- `core/security/response_scanner.{cpp,h}`（头文件在 `include/security/`，M4 新增）— **上游响应流式安全扫描**（`ResponseScanner`，纯逻辑、宿主可单测）：按 SSE 事件边界（`\n\n`/`\r\n\r\n`）切分，完整事件扫描通过即放行（延迟 ≈ 一个事件）；HTTP 响应头块（`HTTP/` 开头）跳过扫描直接放行；非 SSE 聚合缓冲（上限 256KB），Flush（上游关闭）时整体扫描放行，超上限 fail-open 直通并置 overflow 标志（调用方打 hilog warn）；扫描 = `SecurityDetector::DetectResponse`（只认 BLOCK 级）+ 已启用文件插件 `detect_response` 链。
- `include/json_scan.h` + `include/str_util.h`（R2 新增，header-only 公共件）— 前者是手写最小 JSON 扫描器（`hmsec::JsonCursor`：`ParseString`（含 `\uXXXX` 解码）/`ParseInt`/`SkipValue`/`ParseStringArray` + `JsonEscape`），被 router/security_detector/napi_proxy/proxy_server 共用；后者是 `hmsec::ToLower`。**`core/config/`（旧 ConfigManager）已于 R1 删除**——它从不持久化，唯一调用方是已下线的三个 NAPI 配置函数；配置数据源一直是 ArkTS 侧 `SettingsRepository`。
- `core/plugin/` + `include/aigate_plugin.h` — **动态库插件机制（M2 已落地）**：纯 C ABI（POD 结构 + 函数指针表 + 唯一入口符号 `aigate_plugin_init`，ABI 版本 `AIGATE_PLUGIN_API_VERSION=1` 不匹配即拒载；用纯 C 是因为 C++ 符号/ABI 跨编译单元不稳定）。`PluginManager` 跨平台加载（鸿蒙设备侧 `dlopen`，Windows 宿主单测 `LoadLibrary`），`LoadPluginFromFile`/`LoadPluginsFromDir`（目录不存在返回 0）/`SetPluginEnabled`/`GetPlugins`，统一插件表带互斥锁；加载失败的插件也入表（enabled=false + error）。**内置适配器**把 `aigate::SecurityDetector` 包装成 id 为 `builtin-security-detector` 的内置插件（source=builtin）。鸿蒙现实约束：只能 dlopen 应用沙箱内/随包的 .so，插件目录固定为 `filesDir/plugins`（EntryAbility 启动时扫描，目录不存在则跳过）。**旧 IPlugin 静态工厂注册路径已于 R1 删除**（`IPlugin`/`ISecurityPlugin`/`ITransformPlugin`/`PluginFactory`/`RegisterPlugin`/`InvokePlugin` 等零调用方；对应 NAPI `loadPlugin`/`unloadPlugin`/`getLoadedPlugins` 同步下线）。
- `third_party/mongoose/`（7.22 master 快照，版本记在 `third_party/mongoose/README.md`）。用 `MG_TLS=MG_TLS_MBED` 构建——**不要用 `MG_TLS_BUILTIN`**：它无条件拒绝带扩展的证书，且其 DER 解析器处理不了现代证书链，https 上游根本握不了手。
- `third_party/mbedtls/`（3.6，`include/`+`library/` ~109 个 .c，静态链入 entry）。`psa_crypto_init()` 在 `ProxyServer::Start` 里调一次（3.6 把部分 EC 运算路由到 PSA）。mongoose 通过 `mg_mbed_rng` 驱动握手 RNG（mbedtls <4.0）。**用 3.x 不用 4.x**：4.x 切到 PSA 控制的 RNG，需要额外初始化。无 CA 列表 ⇒ `VERIFY_NONE`（握手成功但不验链，本地可信网关场景可接受）。GLM/百度已端到端验证 `proxy=200`。

转发主流程：`Claude Code → 127.0.0.1:8080 (mg_http_listen，工作线程 ServerEv) → 管线 ResolveRoute（M3：DetectProtocol + ExtractMetadata → Router 规则表，命中用规则上游、未命中回退 CurrentUpstream + ResolveTarget；命中打 hilog 记 ruleId/协议/model，绝不打 apiKey）→ 管线 SecurityCheckRequest（仅对请求体跑 SecurityDetector::DetectRequest，只阻断 BLOCK 级命中）→ 管线 BuildRequest（剔除 hop-by-hop/客户端鉴权头，注入命中上游的网关 Key）→ mg_connect 上游（https 走 mbedTLS 握手，TLS/SNI 按 ConnCtx 里记录的实际转发目标——路由命中时≠默认上游）→ ClientEv MG_EV_READ 回传响应：M4 起若响应检测开启（SetResponseSecurityEnabled，默认开）且有启用的响应侧检测能力（内置检测器或响应插件钩子），ConnCtx 挂 ResponseScanner 按 SSE 事件边界扫描后放行，命中阻断则给本地连接发 SSE 错误事件（data: {"error":{"type":"security_block",...}}）后按 is_draining 优雅关闭、blocked++，上游关闭前 Flush 扫描剩余缓冲防尾部丢失；否则保持零拷贝直通`。每条本地连接与一条上游连接通过 `ConnCtx` 配对，响应字节借此找回本地连接；统计计数器（total/success/blocked/failed）有互斥锁保护；事件循环跑在独立 `std::thread`（`mg_mgr_poll`，200ms），与 NAPI 调用线程隔离。

### ArkTS 层 `entry/src/main/ets/`（分层，依赖向内）

- `types/` — 共享接口唯一数据源：`ProxyTypes`/`SecurityTypes`（`SecurityRule` 含 hitCount/customKeywords/customPatterns）/`PluginTypes`/`Provider`（env 解析助手 + codex 形态助手 `getCodexApiKey`/`getCodexConfigText`/`tomlStringValue`）/`App`（含 `CHANNEL_APPS` 渠道切换表 + `toChannelApp` 回放校验）/`Preset`（`PresetTheme` 带暗色变体 + `presetThemeBackground` 助手）/`EnvKeys`（`EnvKeySet` + `envKeysForApp(app)`：claude 系 `ANTHROPIC_*`、gemini `GOOGLE_GEMINI_*`/`GEMINI_*`、opencode OpenAI 兼容 `OPENAI_BASE_URL`/`OPENAI_MODEL`/`OPENAI_API_KEY`、codex 逻辑键名 `config.base_url`/`config.model`/`OPENAI_API_KEY`——codex 形态非 env，实际解析走 Provider 的 codex 助手）/`RouteRule`（M3 路由规则 + 校验/解析助手）/`Skin`（M5：`SkinPack` + `SKINS` + `skinById`，并导出 `DEFAULT_ACCENT`/`DEFAULT_ACCENT_TINT`——全仓默认强调色唯一来源，禁止再硬编码 '#2563EB'）/`Json`（R3：`jsonStr` 字符串转义 / `strArrayJson` / `parseStringArray` 宽容解析 / `buildCodexJson`——所有契约 JSON 拼接的统一入口，严格模式下骨架仍字符串拼接）。
- `repository/` — 只做持久化（preferences），无业务逻辑：`ProviderRepository`（per-app 供应商 CRUD，曾名 `ProviderStore`）、`SettingsRepository`（**配置唯一数据源**：proxyHost/port/autoStart/securityEnabled + 三渠道本地配置的 URI/原文备份/备份状态（Claude `settings.json`、Codex `config.toml`、OpenCode `opencode.json`）+ `routeRulesJson`（M3）+ `ruleCustomJson`（M4 规则自定义词条，重启回放源）+ `responseSecurityEnabled`（M4）+ `themeMode`（M5）+ `skinId`（M5）+ `activeAppId`（多渠道管理：活动渠道，默认 'claude'）+ 云端 API 地址/设备密钥/ETag/版本/最后有效快照；云端连接变更会清除旧快照）；C++ 侧旧 `ConfigManager` 已于 R1 删除，preferences 是唯一配置数据源）。静态方法单例，在 `EntryAbility.onCreate` 注入 context 初始化（preferences 需要）。
- `services/` — NAPI 薄封装：`ProxyService`（start/stop/getStatus/setUpstream）、`SecurityService`（规则列表/开关/updateRuleConfig/setSecurityEnabled/setResponseSecurityEnabled）、`PluginService`（M2：loadPlugins/listPlugins/setPluginEnabled）、`RouteService`（M3：setRouteRules）；云端拉取由 `CloudConfigurationService`（HTTPS + 设备密钥 + ETag + 最后有效快照）负责；**非 NAPI** 的 `RuleCustomService`（R3 从 GatewayController 下沉：规则自定义词条的持久化↔回放，SettingsRepository.ruleCustomJson + SecurityService.updateRuleConfig）、`LocalConfigService`（picker 管理 Claude/Codex/OpenCode 本地配置的 URI 授权、接管与备份恢复）、`TrayService`（托盘）。
- `app/GatewayController.ets` — 编排/用例层（静态单例，可从 `@Component` 直接调）：活动渠道 `activeAppId` + `setActiveApp`（多渠道管理）、`providerToUpstream`、`applyCurrentProvider`、供应商 CRUD、代理启停、路由规则 CRUD + `applyRouteRules`（M3）、安全词条公开入口（转发给 RuleCustomService，R3 起不再持有其数据逻辑）、云快照校验后只应用安全策略（**云端 `providerPresets` 不进 ProviderRepository**，只经 `getProviderPresets` 进「添加供应商」表单：命中云端预设的渠道**只显示云端预设**，未配置的渠道回退内置预设；旧 `cloud:*` 供应商由 `removeLegacyCloudProviders` 清理）。初始化、供应商变更、代理启动、渠道切换时推送上游配置与路由表——**运行中也能热更新**；本地配置只接管活动渠道，运行中切换渠道先恢复旧文件再改写新文件，停止时兜底恢复全部已接管文件。codex 供应商的 upstream 从 `{auth,config(TOML)}` 形态解析（baseUrl/model 在 TOML 里）；**`cppApiKeyField` 把 OPENAI_API_KEY 映射为 ANTHROPIC_AUTH_TOKEN**——C++ `BuildAuthHeader` 只认三个字段名，OpenAI 兼容的 Bearer 注入与该映射行为一致，故 C++ 零改动。
- `app/ThemeController.ets`（M5）— 外观编排层（静态单例）：`getThemeMode`/`setThemeMode`（持久化 + `ApplicationContext.setColorMode` 即时生效）、`getSkinId`/`setSkinId`（持久化 + 皮肤色值写入 AppStorage `skinAccent`/`skinAccentTint`）、`applyFromSettings`（启动回放）。当前亮暗态经 AppStorage `themeIsDark` 暴露（EntryAbility `onConfigurationUpdate` 刷新）。
- `pages/Index.ets` — 唯一页面，纯视图：`@State` + 薄 handler（`await GatewayController.X()` 后 `refresh()`），只 import `GatewayController` + types + UI 组件，不感知 service/repository/env schema。
- `components/` — `StatusBar`（托盘胶囊）、`Icons`、`common/`（R3：`DialogShell` 对话框骨架（遮罩+标题栏+按钮行，@BuilderParam 内容槽）/ `LabeledInput` / `SectionWidgets`——所有对话框与设置行的统一件）、`settings/`（R3 拆分自原 1224 行 ConfigPanel：`ProxySection`/`AppearanceSection`/`SecuritySection`（含 CustomRuleDialog）/`RouteSection`（含 RouteRuleDialog）/`PluginSection`/`AgentConfigSection`（Claude/Codex/OpenCode 配置关联）/`AboutSection`，各 section 自带 @State/handler，经 SectionPersistHandle 与壳协作）、`ConfigPanel`（壳：标题栏 + 滚动容器 + 分组挂载）、`provider/`（ProviderList/ProviderCard/Add/EditProviderDialog + R3 抽出的 `ProviderFormFields` 公共表单；EditProviderDialog 收 `appId` prop 且键名一律走 `envKeysForApp`；ProviderCard 分类底色按 `themeIsDark` 二选一）。
- `config/` — 预设供应商模板（`PresetRegistry` + Claude/Codex/Gemini/OpenCode 预设；OpenCode 预设走 OpenAI 兼容 env 形态，端点只允许复用现有预设文件里已出现的真实 URL）。

数据流：`UI(Index) → GatewayController → {ProviderRepository, SettingsRepository, ProxyService} → libentry.so`。controller 是唯一组合这些件的地方，视图不直接触碰 service/repository。

~~二期 TODO（数据→代理路径上仅剩的 Claude 耦合）~~ **已完成（M1）**：`envKeysForApp(app)` 已从 `components/provider/AddProviderDialog.ets` 的局部助手抽到 `types/EnvKeys.ets`（`EnvKeySet{baseUrlKey, modelKey, apiKeyField}`，claude 系 `ANTHROPIC_*`，gemini 系 `GOOGLE_GEMINI_*`；多渠道管理又补了 codex/opencode 映射，见 types/ 条目），`GatewayController.providerToUpstream(app, provider)` 的 env 键名解析已以它为准（claude 的 `ANTHROPIC_API_KEY` 优先行为经 `resolveApiKeyField` + `Provider.inferApiKeyField` 保留）。C++ 侧本就接受任意 `apiKeyField`，未改原生代码。

## 代码风格与约定

- 注释/文档用中文；C++ 注释见 `CMakeLists.txt` 风格（中文、解释"为什么"）。
- 供应商配置以 **JSON 字符串**（`settingsConfigJson`，Claude `settings.json` 的 env 形态）携带：`{"env":{"ANTHROPIC_BASE_URL":...,"ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY":...,"ANTHROPIC_MODEL":...}}`。
- **ArkTS 严格模式约束**（改 `.ets` 必读）：
  - 不给 `Record`/索引签名类型写对象字面量（显式 interface 可以）；空 `{}` 可以。
  - 禁用 `delete` 运算符（重建 Record，参考 `ProviderRepository.removeProviderKey`）；接口字段禁用索引访问（用点访问）。
  - 带连字符的字段名转 camelCase（如 `VisibleApps.claudeDesktop`，而 AppId **值**仍是 `'claude-desktop'`）。
  - 每个数据对象都要有 interface；动态 JSON 以**字符串**拼接，不要 `JSON.stringify` 字面量。
  - 不允许悬浮 Promise：要么 `await`，要么 `.then(()=>{}, ()=>{})` fire-and-forget。NAPI 异步方法返回 `Promise`，必须消费。
  - 改 `.ets` 时用项目技能：`arkts-code-check` / `ets-lsp-check`（语言合规 + IDE 级诊断）、`arkui-codegen`（UI 约束）。
- hilog（两侧通用）：C++ 用 `OH_LOG_Print`（宏 `PROXY_LOG`，tag `ProxyEv`，链接 `libhilog_ndk.z.so`）；ArkTS `import { hilog } from '@kit.PerformanceAnalysisKit'`，`hilog.info(DOMAIN, TAG, fmt, ...args)`。格式参数必须 `%{public}s`/`%{public}d`，裸 `%s` 会被掩码为 `<private>`。调试：`hdc shell "hilog -x" | grep <TAG>`。
- Ability→页面传数据走 `AppStorage.setOrCreate` + `@StorageLink`（Ability 无法直接碰页面 `@State`）。

### UI 设计规范（M6 视觉打磨沉淀，改 .ets 必读）

- **质感来自克制，不用渐变**：卡面一律纯色 `card_bg`（曾尝试过运行态绿色渐变，用户反馈"不如纯色"后移除并定为规范）。商业感靠：柔和阴影（低透明度大半径，如 `#0A000000` radius 12）、半透明描边（运行/选中态用 `status_running_border` 这类带 alpha 的描边色，不用实体色 border）、间距节奏与文字层级。
- **圆角**：卡片 16、对话框 20、按钮 10、图标方块 12-14、药丸/分段控件全圆角（height/2）。
- **字号层级**：页面标题 20 Bold / 对话框标题 18 Bold / 卡片主标题 15-17 Medium / 正文 14 / 辅助说明 12 secondary / 统计大数字 20 Bold + 标签 11。
- **交互动效**（PC 鼠标优先）：可点元素统一 `hoverEffect(HoverEffect.Highlight)` + `clickEffect({level: ClickEffectLevel.LIGHT})`（小图标钮用 MIDDLE）；供应商卡片自定义 hover（onHover + 边框/阴影 + `.animation({duration:150})`）；对话框入场统一 `TransitionEffect.OPACITY.combine(scale 0.94).animation({duration:200})`（DialogShell/ConfigPanel 已各加一次，TransitionEffect 自带动画，调用方无需包 animateTo）。
- **状态驱动动效只做细腻的**：运行态呼吸点用递归 `getUIContext().animateTo` 往返（Index.pulseStep，运行中持续、停止自停）；注意呼吸环放大超槽会被 Stack 默认裁剪，需 `.clip(false)`。禁止花哨渐变动画。
- **@Builder 参数传递坑**：基本类型参数按值捕获不随状态刷新（统计格曾因此显示陈旧数字）——需要联动刷新的参数必须包成对象字面量按引用传（如 `StatCell($$: StatCellData)`）。
- **全局 animateTo 已 deprecated**：用 `this.getUIContext().animateTo`。

## 安全注意事项

- 真实 API Key 只存 preferences，永不落盘到 Agent 配置（写入 Claude/Codex/OpenCode 本地配置的都是 `aigate-proxy` 占位 token）。
- **安全检测只查请求体**（`request_pipeline.cpp` 的 `SecurityCheckRequest`，M1 从 `proxy_server.cpp` 的 `RunSecurityCheck` 迁出），刻意排除请求头，避免合法 `Bearer`/`x-api-key` 被误判为密码泄露——不要"顺手"把 header 加进去。M4 响应侧同理：`ResponseScanner` 跳过 `HTTP/` 开头的响应头块，只扫 body/事件数据。**请求侧 `password_leak` 规则已退出同步阻断**（`SecurityCheckRequest` 跳过该规则；响应侧保留，防模型回显凭据）：改为 `QueuePasswordLeakAudit` 把 ≤256KB 请求体副本 `try_lock` 入 `PasswordLeakAudit`（`core/security/password_leak_audit.*`）有界队列，审计线程后台生成**只含脱敏元数据**（类型/位置/协议/model/时间，绝不含原文、命中片段或密钥后缀）的提醒记录；队列满/忙直接丢弃并计数，绝不阻塞转发。受内置插件 `password-leak-audit` 开关与审计总开关双重门控；历史保留最近 200 条 / 30 天，ArkTS 侧 `PasswordLeakAuditService` + `SettingsRepository` 镜像持久化，UI 在设置面板「密码泄露提醒」区（`PasswordLeakAuditSection`）。
- 上游 TLS 为 **VERIFY_NONE**（NDK 无系统 CA；本地可信网关场景可接受）。如需严格校验，须 bundle CA 列表并切 `VERIFY_REQUIRED`。
- `doc/settings.json` 含真实密钥，已在 `.gitignore`；构建配置 `build-profile.json5` 内含本机签名材料路径，不要外发。
- 代码 lint 启用了 `@security/*` 规则（禁不安全 AES/hash/RSA 等），新代码不要触发。
- （已删除，历史记录）`ProxyEngine::SetRequestInterceptor` 曾写字面量 `|| true` 吞掉入参，使安全检测恒启用；M1 修复为尊重入参，R1 起该接口连同零调用的 `RequestInterceptor` 整体删除。安全检测开关现由 `ProxyServer` 的 `security_enabled_`（默认 `true`）承载，行为与修复后一致。

## 平台踩坑速查

这些运行时 API 的坑是项目实际调试时间花去的地方，技能文件覆盖不到：

- **mongoose 锁定 7.22**：API 与网上旧文档/示例不同，`proxy_server.cpp` 就是按 7.22 写的——`mg_str.buf`（非 `.ptr`）、`MG_MAX_HTTP_HEADERS`（非 `MG_MAX_HEADERS`）、`mg_tls_opts.name` 是 `mg_str`（旧版是 `.servername`/`const char*`，用 `mg_str(host.c_str())` 赋值）。若重新 vendor mongoose，要么保持 7.22，要么同步改这些调用点。
- **socket 路径读语义（崩溃雷区）**：本构建走 mongoose 的 socket 路径（非 MIP 用户态协议栈），`MG_EV_READ` 的 `ev_data` 是 `long*` 字节数，数据在 `c->recv`（`c->recv.buf`/`c->recv.len`）；转发后必须 `mg_iobuf_del(&c->recv, 0, c->recv.len)` 排空，否则字节累积重复转发。把 `ev_data` 当 `mg_str*` 解引用 → NULL+8 SIGSEGV。这个 bug 在接入 mbedTLS 前一直潜伏（此前没有上游能完成 TLS 握手）。
- **关闭前待发送**：`ConnCtx` 一端关闭时对端标记 `is_draining`（不是 `is_closing`），让 mongoose 先冲完发送缓冲；否则尾部数据丢失、客户端报 `2300018 partial file`。
- **沙箱外用户文件（最大的坑）**：第三方应用**无法**按裸路径打开沙箱外文件——`@ohos.file.fs` 的 `openSync(path)` 只在沙箱内解析（内核命名空间 + bind-mount 隔离），`/storage/Users/currentUser/.claude/settings.json`、`~/.codex/config.toml`、`~/.config/opencode/opencode.json` 裸路径都不可达。必须走 `@ohos.file.picker`（`@kit.CoreFileKit`），两种模式别搞混：
  - `DocumentViewPicker.select(DocumentSelectOptions)` — 只能选**已存在**文件。文件还不存在时没用（当年 settings.json 的 bug：`select()` 静默返回空，`applyStart` 拿到空 URI 直接 no-op）。
  - `DocumentViewPicker.save(DocumentSaveOptions)` + `newFileNames: ['settings.json'|'config.toml'|'opencode.json']` — 在用户选的位置**创建**新文件并返回可写 URI。要创建应用自有的配置用这个。
  参考实现：`LocalConfigService`——碰任一本地 Agent 配置前先读它并保存首份备份；连续接管不能覆盖备份。
- **Picker URI 仅当次会话有效——必须持久化**：`select()`/`save()` 返回的 URI（`file://docs/storage/Users/currentUser/...`）在应用/进程重启后即失效。用 `fileShare.persistPermission([{uri, operationMode: READ_MODE|WRITE_MODE}])` 持久化（`@kit.CoreFileKit`；需 `ohos.permission.FILE_ACCESS_PERSIST`；**仅 2in1**——用 `canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')` 门控），每次启动再调 `fileShare.activatePermission([...])` 重新激活（持久化但未激活 = 不可用）。能力缺失时（模拟器）降级为当次会话授权并要求重新关联。`fileShare.PolicyInfo` 是 interface `{uri, operationMode}`——这里写对象字面量没问题（被禁的只有 `Record`/索引签名字面量）。
- **读写 picker URI**：`fs.readTextSync(uri)` 直接吃 URI **字符串**（不是 fd）。写：`fs.writeSync(fd, ...)` 要 `ArrayBuffer`（裸 `string` 过不了重载决议）——用 `new util.TextEncoder().encode(text)` 后传 `u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)`；裸 `u8.buffer` 是 `ArrayBufferLike`，匹配不上重载、编译不过。（`writeSync` 也接受文件路径字符串，但 picker URI 必须走 fd 路径。）
- **沉浸式标题栏**：`mainWindow.setWindowDecorVisible(false)`（隐藏标题栏、保留三按钮）在窗口非 freeform/floating 模式时抛 **1300002**。在 `module.json5` 的 ability 上声明 `"supportWindowMode": ["fullscreen","split","floating"]`，用 `mainWindow.isInFreeWindowMode()` 门控，并用 `getTitleButtonRect()` 读按钮行高度做顶部内边距。**模拟器的 WMS 即便在 freeform 下也返回 1300002**——优雅降级（inset=0）。真机 2in1 PC 表现正常。
- **关闭转托盘/常驻**：用户点窗口 X 时保活应用和代理：`mainWindow.on('windowWillClose', () => { ctx.hideAbility(); return Promise.resolve(true); })`——`resolve(true)` **阻止**关闭，`hideAbility()` 隐藏而不销毁。托盘图标（`TrayService.loadStatusBar` + `registerShowOnIconClick`）调 `showAbility` 唤回；状态栏长时任务保进程常驻。
- **ArkUI `Toggle`(Switch) 无默认宽度**：`Toggle({type: ToggleType.Switch, isOn})` 渲染出来约 0 宽（看着"太窄"），须 `.size({width, height})` 按约 2:1 设置（如 `{width:52, height:28}`）。旋钮可见，容易漏看。
- **HAP 安装错误码**：`9568297` = SDK/targetSdkVersion 太新；`9568332 install sign info inconsistent` = 已装包签名不一致——`hdc uninstall com.huawei.myapplication` 后全新安装（`-r` 只在签名本就一致时有效）。
- **本地 Agent 配置流程中不要相信内存状态**：写走 picker URI（可能被重新授权或替换），永远读-改-写（备份原件 → 修改 → 写回；停止时恢复）。不要在 start/stop 之间持有解析好的 JSON/TOML AST——每次从磁盘重读。
- **运行时换肤走 AppStorage 而非资源（M5）**：`resources/base|dark/element/color.json` 是编译期静态产物，运行时改不了；亮暗切换靠 `ApplicationContext.setColorMode` 让系统在 base/dark 资源目录间切换即可，但"皮肤/主题色"必须由 `ThemeController` 把色值 `AppStorage.setOrCreate('skinAccent'/'skinAccentTint')`，组件用 `@StorageLink` 消费。分工：皮肤只管强调色（按钮/开关选中态/高亮），底色与文字色仍走 `$r('app.color.*')` 由系统资源管亮暗。浅底色用 `rgba(...)` 半透明而非实体色，否则要为每套皮肤维护亮暗两份。新增消费组件时 `@StorageLink` 默认值要与 `types/Skin.ets` 默认蓝一致（AppStorage 未初始化前的兜底）。需要"当前是否暗色"时用 AppStorage `themeIsDark`（EntryAbility `onConfigurationUpdate` + 启动回放维护），不要在组件里另起系统查询。

## 文档可信度警告

`README.md` / `docs/ARCHITECTURE.md` / `docs/DEVELOPMENT.md` / `docs/BACKGROUND.md` 已**重写为与实现一致**，可以信任。仍需注意：`third_party/mongoose/README.md` 里写的 `MG_TLS_BUILTIN` 已过时（实际是 `MG_TLS_MBED`）。若文档与源码冲突，**以源码和本文件为准**。

## 项目技能（`.agents/skills/`）

`arkts-code-check`（ArkTS 合规审查）、`ets-lsp-check`（LSP 级诊断）、`arkui-codegen`（ArkUI 约束）、`arkts-code-lookup`（API 查询）、`harmony-build` / `harmony-fix`（构建与错误修复，注意其路径是 macOS 风格，Windows 直接调 `hvigorw`）、`snapshot`（设备截图）、`huawei-docs-scraper`。

> **注意**：`.agents/` 是本机 AI 工具链（含抓取的华为文档，体积大），**不随仓库分发**（已 gitignore）。开源仓库使用者无需关心本节。
