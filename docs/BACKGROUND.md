# AIGate 项目背景与资料

> 本文介绍项目的来龙去脉与设计动机，帮助新读者（包括 AI 编码代理）快速建立全局认识。
> 权威事实来源是根目录 `AGENTS.md`；架构细节见 [ARCHITECTURE.md](ARCHITECTURE.md)，
> 上手指南见 [DEVELOPMENT.md](DEVELOPMENT.md)。

## 项目是什么

AIGate 是一个运行在 **HarmonyOS 2in1（PC）设备**上的本地 LLM API 转发网关：

- Claude Code、Codex、OpenCode 等 Agent 工具指向 `http://127.0.0.1:<port>`；
- 网关把请求转发到用户在应用内配置的上游 LLM 供应商，并在**服务端注入真实 API Key**；
- 转发前后经 C++ 安全检测引擎筛查（提示注入 / 恶意工具调用 / 密码泄露审计）；
- 支持系统托盘常驻与 SSE 流式透传。

## 为什么做这个

直接给 Agent 工具配置 API Key 有三个痛点：

1. **密钥散落**：每个 Agent 工具的配置文件（`settings.json` / `config.toml` /
   `opencode.json`）都要明文写一份真实 Key，文件被同步、截图或误提交即泄露。
   AIGate 把 Key 收敛到应用偏好（ArkData preferences）统一保管，Agent 本地配置里
   写入的只是 `aigate-proxy` 占位 token。
2. **换供应商要改多处**：不同供应商的 `baseUrl`、鉴权头格式、模型名各不相同。
   AIGate 在网关侧统一注入鉴权头（`x-api-key` / `Authorization: Bearer` /
   `x-goog-api-key`），切换供应商只在应用内点一下，运行中的代理热更新上游。
3. **Agent 流量缺少安全审计**：提示注入、被诱导的恶意工具调用、把凭据回显进响应
   等风险没有现成的本地观测手段。AIGate 的 C++ 规则引擎在请求/响应两侧做本地检测，
   数据不出本机。

## 核心设计决策

| 决策 | 取舍 |
| --- | --- |
| 本地单端口网关 + 活动渠道切换 | 贴合 cc-switch 的切换式交互；C++ 侧渠道无关、零改动。每 Agent 一个端口的方案已否决 |
| 密钥只存 preferences，永不下发到 Agent 配置 | 泄露面收敛到一台设备的一个应用沙箱 |
| C++17 做转发与检测，经 NAPI 桥接 | 转发热路径与规则引擎不依赖 ArkTS 运行时；纯逻辑层可在 Windows 宿主跑单测（307 个用例，无需设备） |
| vendored cpp-httplib 0.54.1 + mbedTLS 3.6 | 零外部依赖构建；MIT 宽松许可，闭源友好（mongoose 因 GPL-2.0 双许可已被替换） |
| 手写最小 JSON 扫描、不引 JSON 库 | 结构固定的契约 JSON 由 ArkTS 生成；规避大 body 性能开销与依赖膨胀 |
| 上游 TLS `VERIFY_NONE` | NDK 无系统 CA 列表；本地可信网关场景可接受，严格校验需自 bundle CA |
| 云端配置只做"预设下发" | 设备经 HTTPS + 设备密钥 + ETag 拉取已发布快照；真实 Key 仍只在本地录入，云端预设只进入"添加供应商"表单 |

## 演进历程

- **2026-07 初** — 项目启动：HarmonyOS 骨架 + mongoose 转发代理跑通。
- **2026-07 中** — HTTPS 上游打通（mbedTLS 接入，修复 mongoose socket 路径读语义
  崩溃雷区），GLM / 百度端到端验证 `proxy=200`。
- **2026-08** — 网络栈从 mongoose（GPL-2.0-only / 商业双许可）整体迁移到
  cpp-httplib（MIT），转发模型改为「pump 线程 + 有界队列桥接」，项目整体改以
  MIT 发布。
- **M0** — 开源配套基线：README / LICENSE / NOTICE / CONTRIBUTING / CI。
- **M1–M3** — 架构解耦：转发管线抽纯逻辑步骤；纯 C ABI 动态库插件机制；多协议
  识别（Anthropic / OpenAI / Gemini）+ 规则路由表。
- **M4** — 安全检测深化：响应侧流式扫描（ResponseScanner）、上下文注入规则、
  规则自定义词条与命中计数；请求侧密码泄露退出同步阻断，改为**异步脱敏审计**。
- **M5** — 主题与皮肤：跟随系统/亮/暗三段切换 + 多皮肤强调色（AppStorage 运行时换肤）。
- **R1–R3** — 重构收尾：C++ 死代码清除与公共抽取；ArkTS 分层收敛（types →
  repository → services → controller → view）；ConfigPanel 拆分为独立设置分区。
- **多渠道管理** — Claude Code / Codex / OpenCode 三渠道统一管理，本地配置接管
  （运行只改活动渠道，停止/切换自动恢复备份）。
- **云端控制面** — `cloud/` 下新增 Spring Boot 后端 + React 控制台：设备管理、
  配置发布（版本 + ETag）、安全策略下发、遥测汇总。

## 目录一览

```
aigate/
├── entry/src/main/cpp/    # C++ 核心：转发代理 + 安全检测 + 插件（libentry.so）
├── entry/src/main/ets/    # ArkTS 层：types → repository → services → controller → view
├── cloud/                 # 云端控制面：Spring Boot 后端 + React 控制台（可选部署）
├── docs/                  # 架构文档 / 开发指南 / 本文
└── AGENTS.md              # 面向 AI 编码代理的权威项目指南
```

## 参考与致谢

- [cc-switch](https://github.com/farion1231/cc-switch) —— UI 与供应商模型移植自该项目
- [cpp-httplib](https://github.com/yhirose/cpp-httplib) 0.54.1 —— 网络栈（MIT）
- [mbedTLS](https://github.com/Mbed-TLS/mbedtls) 3.6 —— TLS 后端（Apache-2.0）
