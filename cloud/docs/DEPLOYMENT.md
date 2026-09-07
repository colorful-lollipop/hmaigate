# 部署与运行

## 运行组成

| 组件 | 默认端口 | 职责 |
| --- | --- | --- |
| `backend` | `8088` | 管理 API、设备配置 API、SQLite 数据库 |
| `console` | `5173`（开发） | 渠道、供应商、安全策略和设备密钥的运营界面 |

后端默认使用 SQLite 文件 `cloud/backend/aigate-cloud.db`，首次启动会自动创建。
这适合单机运营环境和首期交付；SQLite 不适合多个后端实例并发写入。扩容到多副本前，
应迁移到 PostgreSQL 并加入 Flyway/Liquibase 迁移。

## 前置条件

- JDK 21（Maven 可用更高版本 JDK 编译 `--release 21`）；
- Maven 3.9+；
- Node.js 20+ 与 npm；
- 生产环境必须提供 HTTPS 反向代理。

Maven 默认使用用户目录下 `~/.m2/settings.xml` 的 `localRepository` 指定的本地仓库
缓存依赖。若 Maven 在受限沙箱中报该目录权限错误，属于沙箱隔离；正常主机终端直接
运行 Maven 即可使用该缓存。

## 开发启动

```powershell
# 终端一：后端
cd cloud/backend
mvn spring-boot:run

# 终端二：控制台
cd cloud/console
npm install
npm run dev
```

访问：

- 管理台：`http://localhost:5173`
- 健康检查：`http://localhost:8088/actuator/health`
- API 根：`http://localhost:8088/api/v1`

控制台登录名默认是 `admin`；测试默认密码为 `111111`，可通过
`AIGATE_ADMIN_PASSWORD` 覆盖。该密码只用于本机测试，绝不能用于任何网络可达的环境。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PORT` | `8088` | API 监听端口 |
| `AIGATE_ADMIN_USERNAME` | `admin` | 初始运营员帐号 |
| `AIGATE_ADMIN_PASSWORD` | `111111` | 测试运营员密码，生产环境必须覆盖 |
| `AIGATE_ALLOWED_ORIGINS` | `http://localhost:5173,http://127.0.0.1:5173` | 逗号分隔的管理台来源白名单 |
| `SPRING_DATASOURCE_URL` | `jdbc:sqlite:./aigate-cloud.db` | SQLite JDBC URL |
| `VITE_API_BASE_URL` | `http://localhost:8088/api/v1` | 控制台构建时的 API 地址 |

## 构建与验证

```powershell
cd cloud/backend
mvn test
mvn package

cd ../console
npm run build
```

后端 jar 位于 `backend/target/aigate-cloud-0.1.0.jar`，可用下列方式启动：

```powershell
java -jar target/aigate-cloud-0.1.0.jar
```

## 数据与备份

停服后复制 `cloud/backend/aigate-cloud.db` 即可完成一致性备份。运行中如需在线备份，
使用 SQLite 的 `.backup` 命令或支持 SQLite 在线快照的备份工具，不能只拷贝 `-wal` 之外
的单个文件。设备密钥数据库中只存 BCrypt 哈希，密钥明文无法从备份恢复。

## 生产最小安全线

1. 将 API 和控制台部署在 HTTPS 后；设备侧必须校验证书，不能信任任意证书。
2. 把管理 API 放到 VPN、零信任网关或仅内部网段，Basic Auth 仅作为 bootstrap 认证。
3. 用长随机值覆盖 `AIGATE_ADMIN_PASSWORD`，并定期轮换；后续接入 OIDC/企业 SSO 时，
   将 `/api/v1/admin/**` 替换为基于身份与组织的授权。
4. 仅给设备 API 签发最小数量的设备密钥；遗失设备立即在运营台撤销或轮换密钥。
5. 配置、反向代理和日志中不得记录 `X-AIGate-Device-Key`、用户 API Key 或完整遥测正文。

## Docker

仓库包含后端与运营台的 Docker 构建文件，`docker-compose.yml` 会将 SQLite 数据卷挂载为
`/app/data`。启动前必须通过环境变量提供随机管理密码：

```powershell
cd cloud
$env:AIGATE_ADMIN_PASSWORD = 'replace-with-a-long-random-password'
$env:AIGATE_ALLOWED_ORIGINS = 'http://<server>:18080'
docker compose up --build -d
```

Compose 会在 `18080` 暴露控制台，静态资源与 `/api/v1` 反向代理为同一 HTTP 源；后端 `8088`
只绑定到服务器回环地址，不直接暴露。开发期可访问
`http://<server>:18080`。生产环境应由 HTTPS 反向代理终止 TLS，并将外部访问收敛到 HTTPS
入口；设备端不接受 HTTP 云配置地址。
