# AIGate Cloud

`cloud/` 是 AIGate 的运营控制面，和 HarmonyOS 本地网关解耦。它提供两类能力：

- 运营人员在 Web 控制台维护渠道草稿、发布渠道目录和安全策略；
- 设备以设备密钥拉取已发布的无密钥配置，并上报匿名化运行与安全事件。

真实上游 API Key 仍只存 HarmonyOS 本地 preferences。云端禁止保存、下发或在遥测中接收这类密钥。

## 目录

```text
cloud/
├── backend/       Spring Boot 3 / Java 21 API
├── console/       React + TypeScript + Vite 运营台
├── docs/          部署、OpenAPI 与端侧接入契约
└── docker-compose.yml
```

## 本地启动

需要 JDK 21、Maven 3.9+、Node.js 20+ 与 npm。后端默认使用 SQLite，首次启动会在
`cloud/backend/aigate-cloud.db` 创建数据库，不需要另行安装数据库服务。

```powershell
# 终端一：API（默认使用 ./aigate-cloud.db，测试密码为 111111）
cd cloud/backend
mvn spring-boot:run

# 终端二：运营台
cd cloud/console
npm install
npm run dev
```

浏览器打开 `http://localhost:5173`。运营台登录帐号默认 `admin`，测试密码为
`111111`（可通过 `AIGATE_ADMIN_PASSWORD` 覆盖）。服务第一次启动会创建一条默认安全策略；渠道及其供应商预设由
运营人员创建。

生产环境运行方式、配置和端侧集成请阅读 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)、
[docs/DEVICE_INTEGRATION.md](docs/DEVICE_INTEGRATION.md) 与
[docs/API.md](docs/API.md)。

## 安全边界

- 管理 API 走 HTTP Basic，适合作为初始部署的 bootstrap 认证；生产环境应置于 HTTPS、
  VPN/零信任网关之后，并在后续接入 OIDC/企业 SSO。
- 设备 API 仅接受服务端签发的设备密钥；密钥仅在创建/轮换时返回一次，数据库只存 BCrypt 哈希。
- 发布采用草稿与已发布快照分离。设备永远只会读到最后一次成功发布的快照；编辑草稿不影响在线设备。
- 后端会拒绝渠道配置中的明显凭据字段和值。该检查是防误操作的第二道门，不替代访问控制和日志脱敏。

## 许可

云端代码与仓库根目录保持 GPL-2.0-only 许可，详见根目录 `LICENSE`。
