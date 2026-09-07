# Repository Guidelines

## 项目结构

`backend/` 是 Spring Boot 3（Java 21）控制面：业务代码位于
`src/main/java/com/aigate/cloud/`，按 `config`、`domain`、`repository`、`service`、`web`
分层；集成测试位于 `src/test/java/`。`console/` 是 React + TypeScript + Vite
运营台，页面和 API 客户端在 `src/`。`docs/` 保存 API、部署和端侧接入契约；修改设备
协议时同步更新 `docs/API.md` 与 `docs/DEVICE_INTEGRATION.md`。

## 构建、测试与本地运行

在 `backend/` 执行 `mvn test` 运行 Spring 集成测试，`mvn package` 生成可执行 JAR，
`java -jar target/aigate-cloud-0.1.0.jar` 启动 API（默认 `8088`、SQLite 文件
`aigate-cloud.db`）。在 `console/` 执行 `npm install`、`npm run dev` 启动 Vite，
`npm run build` 做 TypeScript 检查并生成 `dist/`。本地测试登录为 `admin / 111111`；
生产环境必须设置 `AIGATE_ADMIN_PASSWORD`。

## 代码风格

Java 使用 2 空格缩进、Spring 构造器注入和清晰的分层边界：Controller 只处理 HTTP，
Service 承载事务和业务规则，Repository 不泄露到 Web 层。DTO 使用 `record`，类名使用
`PascalCase`，变量和 JSON 字段使用 `camelCase`。React 组件使用 `PascalCase`，hooks 和
函数使用 `camelCase`；类型定义集中在 `console/src/types.ts`，API 调用集中在 `api.ts`。

## 测试要求

后端测试使用 JUnit 5、MockMvc 和独立 SQLite 测试库。新增发布、鉴权、配置快照或安全
校验时，在 `CloudApiIntegrationTest` 中补充成功与拒绝路径。前端至少执行 `npm run build`。
涉及设备配置时，验证已发布快照、`ETag` 304 和不包含真实密钥。

## 提交与安全

沿用 Conventional Commits，例如 `feat(cloud): add provider preset`、
`fix(cloud): allow loopback cors origin`。PR 要说明 API/配置影响、测试命令；运营台视觉
修改附截图。不要提交 SQLite 数据库、设备密钥、用户 API Key 或生产密码。供应商模板仅能
保存 `{{apiKey}}` 等占位符，真实凭据始终留在设备端。
