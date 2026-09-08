# 平台踩坑速查（Pitfalls）

> 运行时 API 的坑是项目实际调试时间花去的地方，技能文件覆盖不到。改到相关代码时按需查阅本文。
> 权威事实来源仍是根目录 `AGENTS.md`；若本文与源码冲突，以源码为准。

## C++ / cpp-httplib / mbedTLS

- **open_stream 不能用于本网关**：`StreamHandle` 把 socket 所有权移交给私有字段，外部无法主动中断挂起的 `read()`——`Stop()` 最坏要等上游读超时。用缓冲式 `send()` + pump 线程 + 有界队列桥接（见 `proxy_server.cpp`）：请求进行中 `Client::stop()` 会 shutdown socket（`ClientImpl::stop` 明确这是线程安全的唯一手段），泵立即解阻塞。
- **`Client::set_path_encode(false)` 必须开**：默认 `path_encode_=true` 会对转发路径做 `encode_request_target`，把已编码的 `%xx` 二次编码（`%20`→`+` 之类）；转发目标路径由 `ResolveTarget/JoinUrl` 拼好（含 query），必须原样上送。
- **转发头必须剥 `Accept-Encoding`**：本构建未编 zlib，上游回 gzip 响应时 `content_receiver` 会以 `UnsupportedContentEncoding` 失败；剥掉即「只收未压缩响应」。
- **chunked provider 场景响应头要剥 `Content-Length`/`Transfer-Encoding`/`Connection`**：httplib 对 `set_chunked_content_provider` 自动用 chunked 帧并自己写 `Connection`；保留上游旧值会与本地帧冲突。`Content-Type` 单独经 `set_chunked_content_provider` 的参数写入（`set_header` 是 append 语义，重复写入会出现两个头）。
- **`Server::listen()` 阻塞**（bind + accept 循环 + 线程池 shutdown 全在调用线程内）：必须放 worker 线程跑，`Start` 用 `wait_until_ready()` 等 bind 结果、`is_running()` 判成败。
- **httplib 默认开 `SO_REUSEPORT`**（`create_server_socket`，Linux 下可用即启用）：两个 Server 实例能**同时** LISTEN 同一地址端口，内核对新连接做负载均衡。一旦 `Start` 的防重入闸门失效（曾因 `running_` 忘了在 bind 成功后置位：UI 恒显未启动、`Stop` 因 `exchange(false)` 失败而空转、重复 Start 各起一个 Server），就会出现"请求时而 404、时而正常、日志全无"的诡异组合——泄漏的 socket 上连接被分给已析构/无循环的实例。教训：listen 类启动函数的运行标志必须在成功路径同步置位，`Stop`/`Snapshot`/防重入全押在它上面。
- **`Content-Type` 必须在响应头剥离时单独捕获**：剥离是为了防 `set_chunked_content_provider` 重复写入，但上游头名大小写不定（Node 系全小写 `content-type`），事后从复制表按 `"Content-Type"` 查是查不到的——只能发布头时原样取走存入上下文，否则所有响应都落到 `application/octet-stream` 兜底（SSE 客户端靠这个头识别事件流，会直接解析失败）。
- **`ResponseScanner::Feed` 只在事件边界释放字节，pump 收尾必须 `Flush()`**：非 SSE 响应（JSON 错误体、普通应答）没有 `\n\n` 边界，body 会整体滞留在扫描器缓冲里——`send` 返回后若直接 `queue.Close()`，这些 body 被整段吞掉，客户端只见 200/4xx + 空 body（SSE 流因为事件有边界恰好能透传，极易漏测）。判定手法：同一请求直连上游有 body、经网关没有，且 200 与 4xx 都空。
- **provider 资源释放器是收尾点**：`Response` 析构必调 `content_provider_resource_releaser(success)`——在此 `CloseAndDrop` 队列 + `Client::stop()` + 注销在途表，保证 pump（detach 线程，shared_ptr 保活）及时退出。
- **历史包袱（mongoose 时代，供考古）**：`MG_EV_READ` 的 `ev_data` 是 `long*`、转发后要 `mg_iobuf_del` 排空、对端关闭标记 `is_draining` 冲发送缓冲——这些坑已随 mongoose 移除不复存在。
- **std::regex 中文坑**（`security_detector.cpp`）：std::regex 按字节匹配，可选中文必须写 `(的)?` 分组，`的?` 永不匹配。

## ArkTS / ArkUI

- **ArkUI `Toggle`(Switch) 无默认宽度**：`Toggle({type: ToggleType.Switch, isOn})` 渲染出来约 0 宽（看着"太窄"），须 `.size({width, height})` 按约 2:1 设置（如 `{width:52, height:28}`）。旋钮可见，容易漏看。
- **`Toggle.onChange` 在程序化 isOn 回写时同样触发**：`isOn` 绑定 `@State` 时，启动请求在途、框架把开关同步回 OFF 的那次回写也会发 `onChange`——不去抖就是"点一次、启动两次"（连点/误停/重复计数）。`onChange` 回调带上值与端态比较（值 === 当前状态直接忽略）+ 操作进行中标志，双保险（见 `Index.ets` `toggleProxy`）。
- **@Builder 参数传递坑**：基本类型参数按值捕获不随状态刷新（统计格曾因此显示陈旧数字）——需要联动刷新的参数必须包成对象字面量按引用传（如 `StatCell($$: StatCellData)`）。
- **全局 animateTo 已 deprecated**：用 `this.getUIContext().animateTo`。

## 沙箱外文件与 picker（最大的坑）

- **第三方应用无法按裸路径打开沙箱外文件**——`@ohos.file.fs` 的 `openSync(path)` 只在沙箱内解析（内核命名空间 + bind-mount 隔离），`/storage/Users/currentUser/.claude/settings.json`、`~/.codex/config.toml`、`~/.config/opencode/opencode.json` 裸路径都不可达。必须走 `@ohos.file.picker`（`@kit.CoreFileKit`），两种模式别搞混：
  - `DocumentViewPicker.select(DocumentSelectOptions)` — 只能选**已存在**文件。文件还不存在时没用（当年 settings.json 的 bug：`select()` 静默返回空，`applyStart` 拿到空 URI 直接 no-op）。
  - `DocumentViewPicker.save(DocumentSaveOptions)` + `newFileNames: ['settings.json'|'config.toml'|'opencode.json']` — 在用户选的位置**创建**新文件并返回可写 URI。要创建应用自有的配置用这个。
  参考实现：`LocalConfigService`——碰任一本地 Agent 配置前先读它并保存首份备份；连续接管不能覆盖备份。
- **Picker URI 仅当次会话有效——必须持久化**：`select()`/`save()` 返回的 URI（`file://docs/storage/Users/currentUser/...`）在应用/进程重启后即失效。用 `fileShare.persistPermission([{uri, operationMode: READ_MODE|WRITE_MODE}])` 持久化（`@kit.CoreFileKit`；需 `ohos.permission.FILE_ACCESS_PERSIST`；**仅 2in1**——用 `canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')` 门控），每次启动再调 `fileShare.activatePermission([...])` 重新激活（持久化但未激活 = 不可用）。能力缺失时（模拟器）降级为当次会话授权并要求重新关联。`fileShare.PolicyInfo` 是 interface `{uri, operationMode}`——这里写对象字面量没问题（被禁的只有 `Record`/索引签名字面量）。
- **读写 picker URI**：`fs.readTextSync(uri)` 直接吃 URI **字符串**（不是 fd）。写：`fs.writeSync(fd, ...)` 要 `ArrayBuffer`（裸 `string` 过不了重载决议）——用 `new util.TextEncoder().encode(text)` 后传 `u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength)`；裸 `u8.buffer` 是 `ArrayBufferLike`，匹配不上重载、编译不过。（`writeSync` 也接受文件路径字符串，但 picker URI 必须走 fd 路径。）
- **本地 Agent 配置流程中不要相信内存状态**：写走 picker URI（可能被重新授权或替换），永远读-改-写（备份原件 → 修改 → 写回；停止时恢复）。不要在 start/stop 之间持有解析好的 JSON/TOML AST——每次从磁盘重读。

## 窗口 / 托盘 / 常驻

- **沉浸式标题栏**：`mainWindow.setWindowDecorVisible(false)`（隐藏标题栏、保留三按钮）在窗口非 freeform/floating 模式时抛 **1300002**。在 `module.json5` 的 ability 上声明 `"supportWindowMode": ["fullscreen","split","floating"]`，用 `mainWindow.isInFreeWindowMode()` 门控，并用 `getTitleButtonRect()` 读按钮行高度做顶部内边距。**模拟器的 WMS 即便在 freeform 下也返回 1300002**——优雅降级（inset=0）。真机 2in1 PC 表现正常。
- **关闭转托盘/常驻**：用户点窗口 X 时保活应用和代理：`mainWindow.on('windowWillClose', () => { ctx.hideAbility(); return Promise.resolve(true); })`——`resolve(true)` **阻止**关闭，`hideAbility()` 隐藏而不销毁。托盘图标（`TrayService.loadStatusBar` + `registerShowOnIconClick`）调 `showAbility` 唤回；状态栏长时任务保进程常驻。

## 外观 / 换肤

- **运行时换肤走 AppStorage 而非资源（M5）**：`resources/base|dark/element/color.json` 是编译期静态产物，运行时改不了；亮暗切换靠 `ApplicationContext.setColorMode` 让系统在 base/dark 资源目录间切换即可，但"皮肤/主题色"必须由 `ThemeController` 把色值 `AppStorage.setOrCreate('skinAccent'/'skinAccentTint')`，组件用 `@StorageLink` 消费。分工：皮肤只管强调色（按钮/开关选中态/高亮），底色与文字色仍走 `$r('app.color.*')` 由系统资源管亮暗。浅底色用 `rgba(...)` 半透明而非实体色，否则要为每套皮肤维护亮暗两份。新增消费组件时 `@StorageLink` 默认值要与 `types/Skin.ets` 默认蓝一致（AppStorage 未初始化前的兜底）。需要"当前是否暗色"时用 AppStorage `themeIsDark`（EntryAbility `onConfigurationUpdate` + 启动回放维护），不要在组件里另起系统查询。

## 构建 / 安装

- **HAP 安装错误码**：`9568297` = SDK/targetSdkVersion 太新；`9568332 install sign info inconsistent` = 已装包签名不一致——`hdc uninstall com.huawei.myapplication` 后全新安装（`-r` 只在签名本就一致时有效）。
- **hdc 路径**：安装时路径必须用相对路径；hdc 会把 POSIX `/e/...` 路径搞坏。
