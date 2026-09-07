# API 契约

API 前缀为 `/api/v1`，JSON 编码为 UTF-8。错误统一形如：

```json
{
  "timestamp": "2026-08-18T14:00:00Z",
  "status": 400,
  "code": "bad_request",
  "message": "错误说明"
}
```

## 认证

| 受众 | 路径 | 认证 |
| --- | --- | --- |
| 运营控制台 | `/admin/**` | HTTP Basic，角色 `OPERATOR` |
| HarmonyOS 设备 | `/device/**` | `X-AIGate-Device-Key` |

设备密钥格式为 `agdk_<device-uuid>_<random>`，仅创建或轮换时返回明文。后端仅保存其
BCrypt 哈希。不要把设备密钥放进 URL、日志、遥测 `attributes` 或截图。

## 管理 API

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/admin/overview` | 已发布版本、设备数和近 24 小时安全事件 |
| `GET`/`POST` | `/admin/channels` | 查询/创建渠道草稿 |
| `PUT` | `/admin/channels/{id}` | 更新渠道草稿，`code` 不可改 |
| `POST` | `/admin/channels/{id}/publish` | 发布渠道快照 |
| `POST` | `/admin/channels/{id}/archive` | 下线渠道并推进配置版本 |
| `GET`/`POST` | `/admin/providers` | 查询/创建供应商预设草稿 |
| `PUT` | `/admin/providers/{id}` | 更新供应商草稿，`code` 不可改 |
| `POST` | `/admin/providers/{id}/publish` | 发布供应商；所属渠道必须已发布且启用 |
| `POST` | `/admin/providers/{id}/archive` | 下线供应商 |
| `GET`/`PUT` | `/admin/security-policy` | 查询/保存安全策略草稿 |
| `POST` | `/admin/security-policy/publish` | 发布安全策略 |
| `GET`/`POST` | `/admin/devices` | 查询设备/签发设备密钥 |
| `POST` | `/admin/devices/{id}/rotate-key` | 轮换设备密钥，明文只返回这一次 |
| `POST` | `/admin/devices/{id}/revoke` | 撤销设备访问 |

渠道和供应商新增、编辑只写入草稿；设备只会读取最后一次成功发布的快照。每次发布或下线
都会递增全局 `configVersion`。

## 设备配置 API

### 拉取快照

```http
GET /api/v1/device/config HTTP/1.1
X-AIGate-Device-Key: agdk_...
If-None-Match: "aigate-config-42"
```

若版本未变，服务返回 `304 Not Modified` 和相同 `ETag`。否则返回 `200`：

```json
{
  "configVersion": 42,
  "generatedAt": "2026-08-18T14:00:00Z",
  "channels": [
    {
      "code": "claude",
      "displayName": "Claude Code",
      "clientType": "claude",
      "protocol": "anthropic",
      "iconKey": "plug",
      "localConfigPathHint": "~/.claude/settings.json",
      "revision": 40,
      "configuration": {
        "schemaVersion": 1,
        "configurationFormat": "settings-json-env",
        "fieldMap": {
          "baseUrlField": "ANTHROPIC_BASE_URL",
          "apiKeyField": "ANTHROPIC_AUTH_TOKEN",
          "modelField": "ANTHROPIC_MODEL"
        }
      }
    }
  ],
  "providerPresets": [
    {
      "code": "glm",
      "displayName": "Zhipu GLM",
      "channelCode": "claude",
      "category": "cn_official",
      "revision": 41,
      "configuration": {
        "schemaVersion": 1,
        "settingsTemplate": {
          "env": {
            "ANTHROPIC_BASE_URL": "{{baseUrl}}",
            "ANTHROPIC_AUTH_TOKEN": "{{apiKey}}",
            "ANTHROPIC_MODEL": "{{model}}"
          }
        },
        "endpointCandidates": ["https://open.bigmodel.cn/api/anthropic"],
        "defaultModel": "glm-5.1"
      }
    }
  ],
  "securityPolicyVersion": 42,
  "securityPolicy": {
    "schemaVersion": 1,
    "requestScanEnabled": true,
    "responseScanEnabled": true,
    "rules": []
  }
}
```

`providerPresets` 只用于端侧“添加供应商”表单的初始值；端侧在用户填写 API Key 并明确保存
前，不得创建或更新本地供应商实例。响应绝不包含设备私有供应商、用户 API Key、设备密钥
哈希、草稿或归档资源。服务会剔除已下线的渠道以及其所属预设。缺少某个端侧支持渠道的
云配置时，端侧必须继续保留该渠道的本地能力与内置预设，不能将其视为禁用。

### 上报遥测

```http
POST /api/v1/device/telemetry HTTP/1.1
X-AIGate-Device-Key: agdk_...
Content-Type: application/json

{
  "eventType": "SECURITY_HIT",
  "severity": "BLOCK",
  "channelCode": "claude",
  "ruleId": "password_leak",
  "occurredAt": "2026-08-18T14:00:00Z",
  "attributes": { "protocol": "anthropic" }
}
```

可用级别为 `INFO`、`WARN`、`BLOCK`、`ERROR`，事件类型必须是大写下划线格式。响应为
`202 Accepted`。`attributes` 最大 16 KB；含 `sk-...`、`AIza...`、Bearer 凭据或敏感字段
实际值的请求会被拒绝。

## 配置模板约束

- 渠道与供应商预设 `code` 是跨版本稳定、只可创建时指定的小写标识；设备应以它作为目录去重键。
- `Channel.localConfigPathHint` 是 `~/.claude/settings.json` 一类的展示提示，帮助用户在
  文件选择器中定位本地配置。它不是可执行路径，云端和应用都不得据此绕过用户授权读写文件。
- `Provider.configuration.settingsTemplate` 只能是模板。所有 API Key、token、secret、
  password 或 authorization 字段只能为空或使用 `{{apiKey}}` 形式的占位符。
- 常用占位符：`{{baseUrl}}`、`{{apiKey}}`、`{{model}}`。端侧填写的真实值只在本地替换，
  不回传云端。
- `iconKey` 是展示标识而非 URL；端侧应维护受信任图标映射，不能把它当作远程资源地址。
