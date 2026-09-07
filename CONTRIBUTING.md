# 贡献指南 / Contributing Guide

## 中文

感谢你关注 AIGate！提交贡献前请先阅读 [AGENTS.md](AGENTS.md)（项目唯一权威事实来源）
和 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)（开发指南）。

### 提交 Issue

- 使用对应的 Issue 模板（Bug 报告 / 功能建议），填写完整信息；
- Bug 报告请附：设备/模拟器、系统版本、复现步骤、相关日志
  （`hdc shell "hilog -x" | grep ProxyEv` 或 ArkTS 侧 TAG）；
- **切勿**在 Issue/PR 中粘贴真实 API Key；`doc/settings.json` 含真实密钥，已
  gitignore，不要提交或外发。

### 分支与提交信息

- 从 `main` 切功能分支，命名如 `feat/xxx`、`fix/xxx`、`docs/xxx`；
- 提交信息遵循约定式提交（Conventional Commits）：
  `feat: ...` / `fix: ...` / `docs: ...` / `refactor: ...` / `test: ...` /
  `chore: ...` / `ci: ...`，必要时加作用域，如 `fix(proxy): ...`；
- 一个 PR 只做一件事，保持 diff 可评审。

### 代码风格要点

- 注释与文档用中文，C++ 注释解释"为什么"；
- ArkTS 严格模式约束（对象字面量、禁 `delete`、悬浮 Promise 等）见 AGENTS.md
  "代码风格与约定"一节；改 `.ets` 请过一遍项目技能 `arkts-code-check` /
  `ets-lsp-check`；
- 改 NAPI 桥接层必须同步 `entry/src/main/cpp/types/libentry/Index.d.ts` 与
  `Types.d.ts`；
- hilog 格式参数必须 `%{public}s`/`%{public}d`。

### PR 流程

1. Fork 并创建功能分支；
2. 提交前本地跑通宿主单测：`bash entry/src/main/cpp/tests/run_host_tests.sh`；
   涉及 ArkTS/构建的改动请确认 `assembleHap` 通过；
3. CI（GitHub Actions，windows 宿主单测）必须通过；
4. PR 描述写清改动动机、方案与验证方式，关联相关 Issue；
5. 等待评审，按评审意见迭代。

### 新增检测规则 / 插件

- 新增安全检测规则：见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) "如何添加安全检测规则"——
  改 `security_detector.{cpp,h}` + 补 `test_security.cpp` 宿主单测；
- 插件机制：动态库插件（C ABI + `dlopen`）M2 已落地——插件只需包含
  `entry/src/main/cpp/include/aigate_plugin.h` 并导出 `aigate_plugin_init`，
  编译为 .so 放入应用 `filesDir/plugins` 即可被加载（ABI 版本不匹配会被拒载）；
  目前请求侧 security 插件已接入转发管线，transform/响应侧接线见 Roadmap，
  有意向请先开 Issue 讨论设计再动手。

---

## English

Thanks for your interest in AIGate! Before contributing, please read
[AGENTS.md](AGENTS.md) (the single authoritative source of truth for this project) and
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

### Filing Issues

- Use the appropriate issue template (bug report / feature request) and fill it out
  completely;
- Bug reports should include: device/emulator, OS version, reproduction steps, and
  relevant logs (`hdc shell "hilog -x" | grep ProxyEv`);
- **Never** paste real API keys into issues or PRs. `doc/settings.json` contains real
  keys, is gitignored, and must never be committed or shared.

### Branches & Commit Messages

- Branch off `main` with names like `feat/xxx`, `fix/xxx`, `docs/xxx`;
- Follow Conventional Commits: `feat: ...` / `fix: ...` / `docs: ...` /
  `refactor: ...` / `test: ...` / `chore: ...` / `ci: ...`, optionally scoped,
  e.g. `fix(proxy): ...`;
- One PR does one thing; keep the diff reviewable.

### Code Style Highlights

- Comments and docs in Chinese; C++ comments explain the "why";
- ArkTS strict-mode constraints (object literals, no `delete`, no floating promises,
  etc.) are documented in AGENTS.md ("代码风格与约定"); run the project skills
  `arkts-code-check` / `ets-lsp-check` after editing `.ets` files;
- Changes to the NAPI bridge must update
  `entry/src/main/cpp/types/libentry/Index.d.ts` and `Types.d.ts` in sync;
- hilog format arguments must be `%{public}s` / `%{public}d`.

### Pull Request Process

1. Fork and create a feature branch;
2. Run the host unit tests locally before submitting:
   `bash entry/src/main/cpp/tests/run_host_tests.sh`; for ArkTS/build changes, make
   sure `assembleHap` succeeds;
3. CI (GitHub Actions, Windows host unit tests) must pass;
4. Describe the motivation, approach, and verification in the PR body; link related
   issues;
5. Wait for review and iterate on feedback.

### Adding Detection Rules / Plugins

- New security rules: see "如何添加安全检测规则" in
  [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — modify `security_detector.{cpp,h}` and add host
  unit tests in `test_security.cpp`;
- Plugin mechanism: dynamic-library plugins (C ABI + `dlopen`) landed in M2 — a plugin
  only needs to include `entry/src/main/cpp/include/aigate_plugin.h` and export
  `aigate_plugin_init`, built as a .so placed under the app's `filesDir/plugins`
  (ABI version mismatch is rejected). Request-side security plugins are wired into the
  forwarding pipeline; transform/response-side wiring is on the Roadmap — please open
  an issue to discuss the design before writing code.
