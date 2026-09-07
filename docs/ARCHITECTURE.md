# AIGate 架构文档

> 本文以源码与根目录 `AGENTS.md` 为准，描述当前实现（不是设计稿）。

## 总览

AIGate 是 HarmonyOS 2in1（PC）上的本地 LLM API 转发网关，整体分两层：

- **ArkTS UI 层**：Stage 模型应用，负责供应商管理、多渠道切换、设置、托盘与编排；
- **C++ 核心**：mongoose 事件驱动转发代理 + mbedTLS + 安全检测 + 插件机制，经 NAPI 桥接为 `libentry.so`（模块名 `"entry"`）。

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
                       │  mongoose + mbedTLS + 管线        │
                       └──────────────────────────────────┘
```

- 数据流单向：`UI → GatewayController → {repository, services} → libentry.so`。
  controller 是唯一组合这些件的地方，视图不直接触碰 service/repository。
- Ability→页面传数据走 `AppStorage.setOrCreate` + `@StorageLink`。
- **持久化唯一数据源是 ArkData preferences**（`SettingsRepository` / `ProviderRepository`，
  静态单例，`EntryAbility.onCreate` 注入 context 初始化）。
- **多渠道管理**：`types/App.ets` 的 `CHANNEL_APPS` 定义 Claude Code / Codex /
  OpenCode 三渠道；活动渠道 `activeAppId` 持久化在 `SettingsRepository`，
  `setActiveApp` = 持久化 + 推该渠道当前供应商 + 重下发路由表。

## C++ 核心的两个命名空间

不要混淆：

- **`namespace hmsec`** — 真实实现。`ProxyServer`（单例）是 mongoose 事件驱动转发代理；
  `request_pipeline.*` 是转发管线纯逻辑（有宿主单测）；`upstream.*` 是纯 URL/鉴权逻辑
  （有宿主单测）。
- **`namespace aigate`** — 旧门面层，持有 NAPI 表面。`ProxyEngine`（单例）只是薄壳，
  `Impl` 把 `Start/Stop/GetStatus/SetUpstream` 委托给 `hmsec::ProxyServer::Instance()`。
  **例外：`SecurityDetector` 是真实现**，由 `request_pipeline` 直接调用。

## 转发主流程

```
Claude Code → 127.0.0.1:8080 (mg_http_listen，工作线程 ServerEv)
  → 管线 ResolveRoute：DetectProtocol + ExtractMetadata → Router 规则表
      （命中用规则上游，未命中/空表回退默认上游 CurrentUpstream + ResolveTarget）
  → 管线 SecurityCheckRequest：仅对请求体跑 SecurityDetector::DetectRequest，
      只阻断「级别→动作」映射为 BLOCK 的命中
  → 管线 BuildRequest：重写 Host、剔 hop-by-hop/客户端鉴权头、注入网关 Key
  → mg_connect 上游（https 走 mbedTLS 握手，TLS/SNI 按实际转发目标）
  → ClientEv MG_EV_READ 回传响应：响应检测开启时 ConnCtx 挂 ResponseScanner
      按 SSE 事件边界流式扫描，BLOCK 命中则回发 SSE 错误事件并优雅关闭；
      否则零拷贝直通
```

要点：

- 每条本地连接与一条上游连接通过 `ConnCtx` 配对，响应字节借此找回本地连接；
- 统计计数器（total / success / blocked / failed）有互斥锁保护；
- 事件循环跑在独立 `std::thread`（`mg_mgr_poll`，200ms），与 NAPI 调用线程隔离；
- 关闭前待发送：一端关闭时对端标记 `is_draining`（不是 `is_closing`），让 mongoose
  先冲完发送缓冲，否则尾部数据丢失（客户端报 `2300018 partial file`）；
- 鉴权头映射（`upstream.cpp::BuildAuthHeader`）：`ANTHROPIC_API_KEY`→`x-api-key`、
  `ANTHROPIC_AUTH_TOKEN`→`Authorization: Bearer`、`GEMINI_API_KEY`→`x-goog-api-key`。
  C++ 侧接受任意 `apiKeyField`，本身 Agent 无关；
- 多协议识别（`core/protocol/protocol_adapter.*`）按路径特征 + body 字段签名识别
  Anthropic / OpenAI / Gemini 协议并提取 `model`/`stream` 元数据，供规则路由使用
  （刻意不引 JSON 库：大 body 性能 + 零依赖）。

### socket 路径读语义（崩溃雷区）

本构建走 mongoose 的 socket 路径（非 MIP 用户态协议栈）：`MG_EV_READ` 的 `ev_data`
是 `long*` 字节数，数据在 `c->recv`；转发后必须 `mg_iobuf_del(&c->recv, 0, c->recv.len)`
排空，否则字节累积重复转发。把 `ev_data` 当 `mg_str*` 解引用会 NULL+8 SIGSEGV。

## TLS 决策

- **mongoose 锁定 7.22**：API 与网上旧文档不同（`mg_str.buf`、`MG_MAX_HTTP_HEADERS`、
  `mg_tls_opts.name` 是 `mg_str`）。重新 vendor 须保持 7.22 或同步改调用点。
- **用 `MG_TLS=MG_TLS_MBED`，不用 `MG_TLS_BUILTIN`**：内置 TLS 无条件拒绝带扩展的证书，
  且其 DER 解析器处理不了现代证书链，https 上游根本握不了手。
- **用 mbedTLS 3.6，不用 4.x**：4.x 切到 PSA 控制的 RNG，需要额外初始化；3.6 经
  `mg_mbed_rng` 驱动握手 RNG，`psa_crypto_init()` 在 `ProxyServer::Start` 调一次
  （3.6 把部分 EC 运算路由到 PSA）。mbedTLS 静态链入 entry。
- **`VERIFY_NONE` 的取舍**：NDK 无系统 CA 列表，握手成功但不验链——本地可信网关
  场景可接受。如需严格校验，须 bundle CA 列表并切 `VERIFY_REQUIRED`。

## 安全检测设计

`core/security/security_detector.{cpp,h}` 是可插拔规则引擎，默认四条规则：
`password_leak`、`prompt_injection`、`malicious_tool_use`（响应侧）、`context_injection`
（保守取向：默认只记录不阻断）。规则支持用户自定义词条/正则（`UpdateRuleConfig`，
互斥锁保护）与原子命中计数；「级别→动作」映射决定 WARN 级命中是否阻断
（`SecurityDetector::IsBlocking` 三处调用方收敛复用）。

- **只查 body，不查头**：请求侧刻意排除 header（避免合法 `Bearer`/`x-api-key` 被
  误判为密码泄露），响应侧跳过 `HTTP/` 开头的响应头块。
- **请求侧密码泄露是异步审计**（`core/security/password_leak_audit.*`）：不阻断转发，
  ≤256KB 请求体副本 `try_lock` 入有界队列，后台线程生成**只含脱敏元数据**（类型/
  位置/协议/model/时间，绝无原文与密钥片段）的提醒记录；队列满即丢弃。保留最近
  200 条 / 30 天，ArkTS 侧 `PasswordLeakAuditService` 镜像持久化，UI 在设置面板
  「密码泄露提醒」区。
- **响应侧流式扫描**（`core/security/response_scanner.*`）：按 SSE 事件边界
  （`\n\n`/`\r\n\r\n`）切分扫描，完整事件通过即放行（延迟 ≈ 一个事件）；非 SSE
  聚合缓冲上限 256KB，超限 fail-open 直通并告警；BLOCK 命中向客户端回发
  `security_block` SSE 错误事件后按 `is_draining` 优雅关闭。
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
