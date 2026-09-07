# HMAIGate —— 鸿蒙大模型 Agent 网关

[English](README_EN.md)

AIGate 是一个运行在 **HarmonyOS 2in1（PC）设备**上的本地 LLM API 转发网关。它监听本地端口，把 Agent 工具（Claude Code 等）的请求转发到你在应用内配置的上游 LLM 供应商，并在服务端注入真实 API Key——密钥只存于应用偏好（ArkData preferences），从不写入 Agent 自身配置。

## 功能特性

- **本地转发代理** — 监听 `127.0.0.1:8080`（端口应用内可改），把 Agent 请求转发到当前供应商的上游 `baseUrl`；支持 SSE 流式透传。
- **密钥不出网关** — 真实 API Key 在服务端注入请求头（`x-api-key` / `Authorization: Bearer` / `x-goog-api-key`），只存 preferences，永不落盘到 Agent 配置（Claude/Codex/OpenCode 本地配置写入的都是占位 token）。
- **HTTPS 上游** — vendored mbedTLS 3.6 提供 TLS（mongoose `MG_TLS_MBED` 后端），GLM / 百度等供应商已端到端验证。
- **安全检测** — C++ 可插拔规则引擎，转发前筛查**请求体**：密码泄露、提示注入、上下文注入（保守 WARN 级只记录），命中返回 403；**响应侧检测已接线（M4）**：流式扫描 SSE 事件（恶意 tool use / 密码泄露命中即拦，向客户端回发 SSE 错误事件）。支持规则自定义词条与命中计数。刻意不检测请求头，避免合法 `Bearer`/`x-api-key` 被误判。
- **系统托盘常驻** — 状态栏托盘图标，关闭窗口转隐藏（`hideAbility`），进程与代理保活，点击托盘图标唤回窗口。
- **应用内供应商管理** — Claude Code、Codex、OpenCode 三渠道的供应商列表、预设模板与增删改查，配置以 preferences 为唯一数据源；切换供应商后运行中的代理热更新上游。
- **本地 Agent 配置集成** — 设置面板可关联 Claude `settings.json`、Codex `config.toml`、OpenCode `opencode.json`；代理运行时只接管当前渠道，停止、切换渠道或取消关联时自动恢复原配置。

## 截图

| 主界面 | 系统托盘 |
| --- | --- |
| ![主界面](docs/images/hm_run.jpeg) | ![托盘](docs/images/hm_tray.jpeg) |

## 快速开始

### 环境要求

- Windows + Git Bash（本仓库的开发环境）
- DevEco Studio SDK，`DEVECO_SDK_HOME` 指向 SDK 根目录
- `hvigorw`、`node`、`ohpm`、MinGW `g++`、`hdc` 在 PATH 中
- 目标设备：HarmonyOS 2in1（PC）真机或模拟器

### 构建 / 安装 / 启动

在仓库根目录执行：

```bash
# 同步依赖
ohpm install

# 构建 HAP（C++ 走 BiSheng 编译器）
DEVECO_SDK_HOME="D:/Program Files/Huawei/DevEco Studio/sdk" \
  hvigorw --mode module -p product=default assembleHap \
  --analyze=normal --parallel --incremental --no-daemon
# 产物：entry/build/default/outputs/default/entry-default-unsigned.hap

# 安装 / 启动（路径必须用相对路径；hdc 会把 POSIX /e/... 路径搞坏）
hdc install -r entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell "aa start -a EntryAbility -b com.huawei.myapplication"
```

> 安装报 `9568332 install sign info inconsistent` 时，先 `hdc uninstall com.huawei.myapplication` 再全新安装。

## 使用方式

1. 打开应用，在供应商面板添加供应商（上游 `baseUrl`、API Key、模型，可用预设模板）；
2. 启动代理（默认监听 `127.0.0.1:8080`，设置面板可改端口）；
3. 在设置面板按需关联当前渠道的本地配置：Claude `~/.claude/settings.json`、Codex `~/.codex/config.toml` 或 OpenCode `~/.config/opencode/opencode.json`（经系统文件选择器授权）；
4. 启动代理后，当前渠道配置会指向 `http://127.0.0.1:<port>` 并使用占位 token；停止、切换渠道或取消关联时自动恢复备份；
5. 之后当前渠道的请求都经过网关转发，真实 Key 由网关注入。

## 架构

```
UI（Index.ets，纯视图）
  → GatewayController（编排/用例层）
    → { ProviderRepository, SettingsRepository, ProxyService }
      → NAPI（libentry.so，模块名 "entry"）
        → hmsec::ProxyServer（mongoose 事件驱动转发 + mbedTLS + 安全检测）
```

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。开发指南见
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)，项目背景与设计动机见
[docs/BACKGROUND.md](docs/BACKGROUND.md)。

## Roadmap

- ~~动态库插件机制~~（M2 已落地：纯 C ABI + `dlopen`，见 `entry/src/main/cpp/include/aigate_plugin.h`）；~~响应侧检测插件接线~~（M4 已落地）；后续：transform 类插件接线
- ~~多协议识别（Anthropic / OpenAI / Gemini）+ 智能路由~~（M3 已落地：protocol_adapter + router，model 前缀/协议/路径匹配，ConfigPanel 可视化配置）
- ~~响应侧安全检测接线（恶意 tool use 规则落地）与上下文注入检测~~（M4 已落地：ResponseScanner 流式扫描 + context_injection 规则 + 规则自定义词条/命中计数）
- ~~主题换肤~~（M5 已落地：跟随系统/亮色/暗色三段切换 + 默认蓝/翠绿/紫罗兰皮肤，AppStorage 运行时换肤）
- 后续：transform 类插件接线、协议互转（OpenAI ↔ Anthropic）、Gemini CLI 渠道开放

## 致谢与参考

- [cc-switch](https://github.com/farion1231/cc-switch) —— UI 与供应商模型移植自该项目
- [mongoose](https://mongoose.ws/) 7.22 —— 网络栈（Cesanta，GPL-2.0-only / 商业双许可）
- [mbedTLS](https://github.com/Mbed-TLS/mbedtls) 3.6 —— TLS 后端（Apache-2.0）

## License

本项目以 **GPL-2.0-only** 发布，见 [LICENSE](LICENSE)。vendored 组件及其许可说明见 [NOTICE](NOTICE)——因 mongoose 的双许可条款，闭源分发须取得 Cesanta 商业许可或替换网络栈。

参与贡献请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
