# AIGate 架构文档

> 本文以源码与根目录 `AGENTS.md` 为准，描述当前实现（不是设计稿）。
> 平台踩坑速查在 `PITFALLS.md`，UI 规范在 `UI-GUIDELINES.md`。

## 总览

AIGate 是 HarmonyOS 2in1（PC）上的本地 LLM API 转发网关，整体分两层：

- **ArkTS UI 层**：Stage 模型应用，负责供应商管理、多渠道切换、设置、托盘与编排；
- **C++ 核心**：cpp-httplib 转发代理 + mbedTLS + 安全检测 + 插件机制，经 NAPI 桥接为 `libentry.so`（模块名 `"entry"`）。

## 分层与数据流

```
┌──────────────────────────────────────────────────────────┐
│ pages/Index.ets（唯一页面，纯视图：@State + 薄 handler）   │
│ components/（StatusBar / ConfigPanel / provider/* 等）     │
└──────────────────────────────────────────────────────────┘
                          │ 只调 GatewayController
┌──────────────────────────────────────────────────────────┐
│ app/GatewayController.ets（编排/用例层，静态单例）          │
│  活动渠道 activeAppId / providerToUpstream / 代理启停       │
└──────────────────────────────────────────────────────────┘
        │                         │                │
┌───────────────┐      ┌──────────────────┐  ┌────────────┐
│ repository/   │      │ services/        │  │ services/  │
│ ProviderRepo- │      │ ProxyService     │  │ LocalConfig│
│ sitory        │      │ SecurityService  │  │ CloudConfig│
│ SettingsRepo- │      │ PluginService    │  │ TrayService│
│ sitory        │      │ RouteService     │  │ （非 NAPI） │
│ (preferences) │      │ （NAPI 薄封装）   │  └────────────┘
└───────────────┘      └──────────────────┘
                               │ NAPI
                       ┌────────▼─────────────────────────┐
                       │ napi/napi_proxy.cpp（模块 "entry"）│
                       └────────┬─────────────────────────┘
                       ┌────────▼─────────────────────────┐
                       │ aigate::ProxyEngine（门面薄壳）    │
                       │  → hmsec::ProxyServer（真实实现）  │
                       │  cpp-httplib + mbedTLS + 管线     │
                       └──────────────────────────────────┘
```

- 数据流单向：`UI → GatewayController → {repository, services} → libentry.so`。
  controller 是唯一组合这些件的地方，视图不直接触碰 service/repository。
- Ability→页面传数据走 `AppStorage.setOrCreate` + `@StorageLink`。
- **持久化唯一数据源是 ArkData preferences**（`SettingsRepository` / `ProviderRepository`，
  静态单例，`EntryAbility.onCreate` 注入 context 初始化）。C++ 侧旧 ConfigManager
  已于 R1 删除；云端快照经校验后写入 SettingsRepository，云端连接变更清除旧 ETag/快照。
- **多渠道管理**：`types/App.ets` 的 `CHANNEL_APPS` 定义 Claude Code / Codex /
  OpenCode 三渠道；活动渠道 `activeAppId` 持久化在 `SettingsRepository`，
  `setActiveApp` = 持久化 + 推该渠道当前供应商 + 重下发路由表。

## C++ 核心的两个命名空间

不要混淆：

- **`namespace hmsec`** — 真实实现。`ProxyServer`（单例）是 cpp-httplib 转发代理；
  `request_pipeline.*` 是转发管线纯逻辑（有宿主单测）；`upstream.*` 是纯 URL/鉴权逻辑
  （有宿主单测）。
- **`namespace aigate`** — 旧门面层，持有 NAPI 表面。`ProxyEngine`（单例）只是薄壳，
  `Impl` 把 `Start/Stop/GetStatus/SetUpstream` 委托给 `hmsec::ProxyServer::Instance()`，
  并记住 Start 时的 host/port 回填 `GetStatus`。R1 已删零调用成员
  （RequestInterceptor/UpdateConfig/上游代理死字段等）。
  **例外：`SecurityDetector` 是真实现**，由 `request_pipeline` 直接调用。

## 转发主流程

```
Agent 工具 → 127.0.0.1:8080（httplib 监听，线程池 handler，catch-all 路由 ".*"）
  → 管线 ResolveRoute：DetectProtocol + ExtractMetadata → Router 规则表
      （命中用规则上游，未命中/空表回退默认上游 CurrentUpstream + ResolveTarget）
  → 管线 SecurityCheckRequest：仅对请求体跑 SecurityDetector::DetectRequest，
      只阻断「级别→动作」映射为 BLOCK 的命中（403 返回）
  → pump 线程向上游 send()（https 走 mbedTLS，TLS 按实际转发目标）：
      转发头重写（剔 hop-by-hop/Accept-Encoding/客户端鉴权头，注入网关 Key，
      Host 由 httplib 按上游生成；set_path_encode(false) 原样透传 path+query）
      响应头经 response_handler 提前发布 → body 字节经 content_receiver 压入
      有界字节队列（4MB 背压）
  → handler 等到响应头后回写状态码/响应头，set_chunked_content_provider 从
      队列排空回传：响应检测开启时 RelayContext 挂 ResponseScanner（扫描在
      泵线程按 SSE 事件边界进行，只有确认安全的字节入队），BLOCK 命中则
      入队一条 SSE 错误事件后关队列；否则直通
  → provider 结束（Response 析构）时资源释放器 stop 上游 Client、注销在途表
```

要点：

- 每条转发一条 pump 线程 + 一个 `RelayContext`（队列/扫描器/统计标志），三方
  （pump、handler、Stop）共享，全部经 shared_ptr 保活；
- 统计计数器（total / success / blocked / failed）有互斥锁保护；
- 监听跑在独立 `std::thread`（httplib `listen()` 阻塞语义），与 NAPI 调用线程隔离；
- **停止有界**：`Stop()` 关监听 socket → 对在途转发 `CloseAndDrop` 队列 +
  `Client::stop()`（进行中请求会 shutdown socket，泵立即解阻塞——httplib 的
  `socket_requests_in_flight_` 语义）→ join worker。绝不等待上游超时；
- 客户端断开：provider `sink.write` 失败 → `CloseAndDrop` + stop 上游 → 泵尽快
  退出，provider 以 Canceled 终止（chunked 写出天然 flush，无尾部丢失问题）；
- 鉴权头映射（`upstream.cpp::BuildAuthHeader`）：`ANTHROPIC_API_KEY`→`x-api-key`、
  `ANTHROPIC_AUTH_TOKEN`→`Authorization: Bearer`、`GEMINI_API_KEY`→`x-goog-api-key`。
  C++ 侧接受任意 `apiKeyField`，本身 Agent 无关；
- 多协议识别（`core/protocol/protocol_adapter.*`）按路径特征 + body 字段签名识别
  Anthropic / OpenAI / Gemini 协议并提取 `model`/`stream` 元数据，供规则路由使用
  （刻意不引 JSON 库：大 body 性能 + 零依赖）。路径特征：`/v1/messages`→anthropic、
  `/v1/chat/completions` 与 `/v1/responses`→openai、`:generateContent`/
  `:streamGenerateContent`→gemini（gemini 的 model 从 uri `/models/<m>:` 兜底）。
- **路由表契约**（`router.cpp::SetRulesFromJson`）：非法 JSON 返回 false 不动旧表，
  空数组 `[]` 关闭路由；规则表以不可变快照整体 swap（热更新安全）。匹配按
  `(modelPrefix 前缀 && protocol && pathPrefix 前缀)`，`priority` 大者优先、
  同优先级按数组顺序。规则 JSON schema 见 `Types.d.ts` 的 `NativeRouteRule`。

### 为什么用 pump 线程桥接而不是 open_stream

httplib 的流式 API `open_stream` 把 socket 所有权移交给 `StreamHandle`
（私有字段），外部无法主动中断挂起的 `read()`——`Stop()` 最坏要等上游 300s 读
超时。缓冲式 `send()` 路径下请求进行中调用 `Client::stop()` 会 shutdown socket
（`ClientImpl::stop` 注释明确这是线程安全的唯一手段），泵立即解阻塞。代价是
多一条线程 + 一段 4MB 有界队列，换取可预测的停止语义。

## TLS 决策

- **cpp-httplib 0.54.1，`CPPHTTPLIB_MBEDTLS_SUPPORT`**：单头库，mbedTLS 后端按
  `MBEDTLS_VERSION_MAJOR` 自适配；TLS 会话/校验开关在 `SSLClient` 上
  （`enable_server_certificate_verification(false)` 等）。
- **用 mbedTLS 3.6，不用 4.x**：4.x 切到 PSA 控制的 RNG，需要额外初始化；3.6 的
  `psa_crypto_init()` 在 `ProxyServer::Start` 调一次（3.6 把部分 EC 运算路由到
  PSA）。mbedTLS 静态链入 entry。
- **`VERIFY_NONE` 的取舍**：NDK 无系统 CA 列表，握手成功但不验链——本地可信网关
  场景可接受。如需严格校验，须 bundle CA 列表。
- **转发头里剥 `Accept-Encoding`**：本构建未编 zlib，若上游回 gzip 响应，泵会因
  `UnsupportedContentEncoding` 失败；剥掉即「只收未压缩响应」。

## 安全检测设计

`core/security/security_detector.{cpp,h}` 是可插拔规则引擎，默认四条规则：
`password_leak`、`prompt_injection`、`malicious_tool_use`（响应侧）、`context_injection`
（保守取向：默认只记录不阻断；`password_leak`/`prompt_injection` 默认级别为 BLOCK
以保持阻断行为）。规则支持用户自定义词条/正则（`UpdateRuleConfig`，
互斥锁保护）与原子命中计数；「级别→动作」映射决定 WARN 级命中是否阻断
（`SecurityDetector::IsBlocking` 三处调用方收敛复用）。
安全检测总开关由 `ProxyServer` 的 `security_enabled_`（默认 true）承载。

- **只查 body，不查头**：请求侧刻意排除 header（避免合法 `Bearer`/`x-api-key` 被
  误判为密码泄露），响应侧跳过 `HTTP/` 开头的响应头块。
- **请求侧密码泄露是异步审计**（`core/security/password_leak_audit.*`）：不阻断转发，
  ≤256KB 请求体副本 `try_lock` 入有界队列，后台线程生成**只含脱敏元数据**（类型/
  位置/协议/model/时间，绝无原文与密钥片段）的提醒记录；队列满即丢弃。保留最近
  200 条 / 30 天，ArkTS 侧 `PasswordLeakAuditService` 镜像持久化，UI 在设置面板
  「密码泄露提醒」区。
- **响应侧流式扫描**（`core/security/response_scanner.*`）：按 SSE 事件边界
  （`\n\n`/`\r\n\r\n`）切分扫描，完整事件通过即放行（延迟 ≈ 一个事件）；非 SSE
  聚合缓冲上限 256KB，超限 fail-open 直通并告警；BLOCK 命中向客户端入队一条
  `security_block` SSE 错误事件后终止泵（chunked 收尾无尾部丢失问题）。
- **插件链**：内置 `SecurityDetector` 包装为 id `builtin-security-detector` 的内置
  插件；已启用的文件来源 security 插件的 `detect_request`/`detect_response` 链式
  调用，任一 BLOCK 即拦截。

## 插件机制

`core/plugin/` + `include/aigate_plugin.h`：纯 C ABI（POD 结构 + 函数指针表 +
唯一入口 `aigate_plugin_init`，ABI 版本不匹配即拒载）。`PluginManager` 跨平台加载
（鸿蒙 `dlopen`，Windows 宿主测试 `LoadLibrary`），加载失败也入表（enabled=false +
error）。插件目录固定 `filesDir/plugins`（沙箱约束：只能加载沙箱内/随包 .so）。
尚未接线：transform 类插件。

## ArkTS 层

`entry/src/main/ets/`，分层依赖向内：

- `types/` — 共享接口唯一数据源（`ProxyTypes` / `SecurityTypes` / `PluginTypes` /
  `Provider`（含 codex TOML 形态助手）/ `App`（CHANNEL_APPS）/ `Preset` / `EnvKeys`
  （`envKeysForApp`）/ `RouteRule` / `Skin` / `Json` 助手）。
- `repository/` — 只做持久化（preferences），无业务逻辑。
- `services/` — `ProxyService` / `SecurityService` / `PluginService` / `RouteService`
  是 NAPI 薄封装；`CloudConfigurationService`（HTTPS 设备配置拉取、ETag 与最后有效
  快照）、`RuleCustomService`、`LocalConfigService`（系统文件选择器管理 Claude
  `settings.json`、Codex `config.toml`、OpenCode `opencode.json`，运行时只接管
  活动渠道，停止/切换时恢复首份备份）与 `TrayService`（托盘）**不是 NAPI**。
- `app/GatewayController.ets` — 编排层；初始化、供应商变更、代理启动、渠道切换时
  推送上游配置与路由表，**运行中也能热更新**；codex 供应商的 upstream 从
  `{auth, config(TOML)}` 形态解析（`cppApiKeyField` 把 `OPENAI_API_KEY` 映射为
  `ANTHROPIC_AUTH_TOKEN`，C++ 零改动）。云端快照校验后只应用安全策略，云端
  `providerPresets` 不进 `ProviderRepository`，只经 `getProviderPresets` 进
  「添加供应商」表单（命中云端预设的渠道只显示云端预设）。
- `pages/` + `components/` — 纯视图与 UI 组件（`ConfigPanel` 为壳，`settings/*`
  各分区自带状态；`ThemeController` 管亮暗切换与皮肤强调色，运行时换肤走
  AppStorage 而非资源目录）。
- `config/` — 预设供应商模板（`PresetRegistry` + Claude/Codex/Gemini/OpenCode 预设）。

供应商配置以 JSON 字符串（`settingsConfigJson`，Claude/OpenCode 的 env 或 Codex TOML 形态）
携带：`{"env":{"ANTHROPIC_BASE_URL":...,"ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY":...,"ANTHROPIC_MODEL":...}}`。

### 云端发布配置

设备只通过 HTTPS `GET /api/v1/device/config` 拉取已发布快照，使用
`X-AIGate-Device-Key` 与 `If-None-Match`。快照经校验后才写入 `SettingsRepository`；
网络或校验失败继续使用最后一次有效快照。本地更换云端地址或设备密钥会清除旧 ETag
与快照，避免跨配置域回放。云端控制面（设备管理 / 配置发布 / 遥测）见 `cloud/`
目录（Spring Boot 后端 + React 控制台，可选部署，见 `cloud/docs/`）。

### 沙箱外文件机制（picker）

第三方应用无法按裸路径打开沙箱外文件（`fs.openSync` 只在沙箱内解析）。读写用户的
`~/.claude/settings.json`、`~/.codex/config.toml`、`~/.config/opencode/opencode.json`
必须走 `@ohos.file.picker`：

- `DocumentViewPicker.select` 只能选已存在文件；要创建新文件用 `save` +
  `newFileNames`；
- picker 返回的 URI 仅当次会话有效，必须 `fileShare.persistPermission` 持久化
  （需 `ohos.permission.FILE_ACCESS_PERSIST`，仅 2in1，用 `canIUse` 门控），每次
  启动再 `activatePermission` 激活；
- 本地 Agent 配置流程不相信内存状态：永远读-改-写（备份原件 → 修改 → 写回；停止时
  恢复备份）；首次备份状态单独持久化，重复接管不会覆盖原文。

参考实现：`services/LocalConfigService.ets`。

## 托盘与常驻

- 关闭窗口 X 时：`mainWindow.on('windowWillClose', ...)` 返回 `resolve(true)` 阻止
  关闭，`hideAbility()` 隐藏而不销毁；
- 托盘图标（`TrayService.loadStatusBar` + `registerShowOnIconClick`）调
  `showAbility` 唤回；状态栏长时任务保进程常驻；
- 沉浸式标题栏 `setWindowDecorVisible(false)` 依赖 floating 窗口模式
  （`module.json5` 声明 `supportWindowMode`），非 freeform 时抛 1300002，需用
  `isInFreeWindowMode()` 门控并优雅降级（模拟器 WMS 即便 freeform 也返回 1300002）。

## 已知边界

- ArkTS 测试（`entry/src/test/`、`entry/src/ohosTest/`）是 stub，真正的测试覆盖在
  C++ 宿主单测（`entry/src/main/cpp/tests/`，`run_host_tests.sh`，307 个用例）；
- transform 类插件尚未接线；
- 上游 TLS 不验链（`VERIFY_NONE`），见上文 TLS 决策。
