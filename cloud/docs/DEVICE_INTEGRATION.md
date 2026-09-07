# HarmonyOS 端侧接入指南

本文件是交给后续端侧 Agent 的契约，不要求本次改动 HarmonyOS 工程。目标是把云端的
**已发布渠道、供应商预设和安全策略**安全地提供给现有本地配置；现有网关继续持有真实
API Key 并继续在本地转发。

## 接入原则

1. 云端是运营目录，不是密钥托管服务。真实 API Key 只写本地 `ProviderRepository` /
   preferences，永不上传。
2. 云端预设仅填充“添加供应商”表单，不能自动创建、覆盖、删除或切换本地供应商；用户 API Key
   始终由用户在端侧填写并保留在 preferences。
3. 云端未下发某个端侧已支持渠道时，该渠道继续使用内置显示名、预设和本地配置接管能力，
   绝不能被隐藏、禁用或清空。
4. `Channel.localConfigPathHint` 仅是文件选择器的展示提示。端侧仍必须通过 picker 获取用户
   授权的 URI，不能按云端路径直接访问沙箱外文件。
5. 拉取失败、证书失败、JSON 解析失败或未知 schema 时必须 fail-open：保留最后一次
   成功快照和本地供应商，不能阻止网关启动。
6. 当前开发部署允许 HTTP/HTTPS 云配置请求；生产环境必须改为 HTTPS。设备密钥以
   preferences 保存，日志中只能显示前缀。

## 建议同步时机

- `EntryAbility.onCreate` 完成本地仓储初始化后异步拉取一次；不得阻塞首页首帧。
- 应用回到前台、用户主动刷新、距离上次成功同步超过 6 小时时再次拉取。
- 保存 `ETag`、`configVersion`、最后成功时间和设备密钥到 `SettingsRepository` 的新增字段。
- 发送 `If-None-Match`。收到 `304` 不做任何本地写入；收到 `200` 后先整体校验，再替换
  预设快照与安全策略；不得对 `ProviderRepository` 执行云端供应商合并。

## 渠道合并

当前 UI 只显示 `CHANNEL_APPS = ['claude', 'codex', 'opencode']`。收到 `channels[]` 时：

1. 仅接受 `code` 在当前 `CHANNEL_APPS` 内且 `configuration.schemaVersion === 1` 的项；
   未支持渠道可缓存为“等待客户端版本支持”，但不要显示为可用。
2. 用 `clientType` 校验云端渠道与 `AppId` 的对应关系；不匹配时跳过并上报 `CONFIG_REJECTED`。
3. 云端渠道的显示名、图标、文件位置提示和表单/模板元数据可更新；不能替代当前活动渠道选择
   `SettingsRepository.activeAppId`。
4. 云端不再下发某渠道时，回退该渠道内置信息；当前本地用户供应商、选中的供应商以及正在
   运行的上游不得强制删除。

## 供应商模板合并

`providerPresets[]` 的每项都关联 `channelCode`，只能在对应渠道已接受后处理。预设可与
内置同名预设合并（云端优先），但其生命周期只存在于预设选择器，不能写入供应商列表。

### Claude/OpenCode 的 env 模板

`configuration.settingsTemplate` 可以是当前项目使用的 JSON 形态：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "{{baseUrl}}",
    "ANTHROPIC_AUTH_TOKEN": "{{apiKey}}",
    "ANTHROPIC_MODEL": "{{model}}"
  }
}
```

端侧只替换允许的 `{{baseUrl}}`、`{{model}}` 和由用户输入的 `{{apiKey}}`；只有用户确认
保存后才写入新的 `Provider.settingsConfigJson`。API Key 字段需要服从 `envKeysForApp(app)` 和
`GatewayController.providerToUpstream` 的现有映射：OpenAI 兼容渠道仍通过
`OPENAI_API_KEY -> ANTHROPIC_AUTH_TOKEN` 注入 C++ Bearer 认证，不能把真实 Key 写入云端。

### Codex 模板

Codex 供应商仍应生成项目现有的 `{auth, config}` 形态：

```json
{
  "auth": { "OPENAI_API_KEY": "{{apiKey}}" },
  "config": "model = \"{{model}}\"\n[model_providers.custom]\nbase_url = \"{{baseUrl}}\""
}
```

端侧使用现有 `buildCodexJson` / TOML 转义助手生成最终 JSON，不要将云端 TOML 原文做不受控
字符串拼接。`baseUrl` 必须是 HTTPS URL，且用户输入的 API Key 不出 preferences。

### 更新规则

- 云端预设版本更新只会更新后续“添加供应商”操作可见的表单初始值。
- 已由用户保存的供应商是独立本地对象，云端更新、下线和同步失败均不得改动其中的 URL、模型、
  API Key、当前选择或正在运行的上游。

## 安全策略映射

云端策略格式：

```json
{
  "schemaVersion": 1,
  "requestScanEnabled": true,
  "responseScanEnabled": true,
  "rules": [
    {
      "ruleId": "password_leak",
      "action": "BLOCK",
      "keywords": ["internal-secret"],
      "patterns": ["example-[0-9]+"]
    }
  ]
}
```

当前原生桥接的安全能力与映射如下：

| 云端字段 | 端侧动作 |
| --- | --- |
| `responseScanEnabled` | `GatewayController.setResponseSecurityEnabled(...)` |
| `rules[].keywords/patterns` | 写入 `SettingsRepository.ruleCustomJson`，再由 `RuleCustomService.applyRuleConfigs()` 回放 |
| `rules[].action = ALLOW` | `SecurityService.setRuleEnabled(ruleId, false)` |
| `rules[].action = BLOCK/WARN` | `SecurityService.setRuleEnabled(ruleId, true)`；现有 C++ 默认动作映射保持不变 |
| `requestScanEnabled` | 记录为端侧策略状态；需在后续端侧实现中接入现有请求安全开关的启动/更新路径 |

注意：当前 NAPI 未暴露“按规则修改 BLOCK/WARN 动作”的接口。因此在端侧未增加该桥接前，
`BLOCK` 与 `WARN` 只能表达运营意图，不能改变 C++ 内置动作映射；不得伪造已生效状态。
未知 `ruleId`、超过限制的词条、非法正则均应跳过并上报 `CONFIG_REJECTED`。

## 遥测

只上传低敏事件，例如：`CONFIG_APPLIED`、`CONFIG_REJECTED`、`SECURITY_HIT`、
`UPSTREAM_FAILURE`。`attributes` 中可包含协议、渠道 code、规则 ID、错误类别和耗时区间；
严禁包含请求体、响应体、URL 查询参数、用户 API Key、Bearer token 或完整本地路径。

上报失败应有指数退避并丢弃超时事件，不能阻塞本地代理转发。安全检测命中和云端同步失败均
应继续以现有本地 hilog 为主，云端遥测仅是运营辅助。
