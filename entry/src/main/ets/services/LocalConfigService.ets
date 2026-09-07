/**
 * LocalConfigService —— 本地 Agent 配置接管（Claude Code / Codex / OpenCode）。
 *
 * 沙箱外文件必须经系统文件选择器取得 URI；代理运行期间写入本地网关地址和占位
 * Token，真实上游 Key 始终只保存在应用 preferences。每次接管先读原文件并保存
 * 备份，停止、切换渠道或取消关联时恢复原文。
 */
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileShare } from '@kit.CoreFileKit';
import { LocalConfigApp } from '../types/App';
import { jsonStr } from '../types/Json';
import { SettingsRepository } from '../repository/SettingsRepository';

const DOMAIN = 0x0000;
const TAG = 'LocalConfigService';
const PLACEHOLDER_TOKEN = 'aigate-proxy';
const DEFAULT_MODEL = 'gpt-5.5';
const CAP_FILE_SHARE = 'SystemCapability.FileManagement.AppFileService.FolderAuthorization';

export class LocalConfigService {
  private static ctx: common.Context | null = null;

  static init(context: common.Context): void {
    LocalConfigService.ctx = context;
  }

  static isLinked(app: LocalConfigApp): boolean {
    return SettingsRepository.getLocalConfigUri(app).length > 0;
  }

  /** 关联配置文件。文件仅在代理运行时接管，避免离线时修改用户本地配置。 */
  static async link(app: LocalConfigApp): Promise<boolean> {
    if (LocalConfigService.ctx === null) {
      hilog.error(DOMAIN, TAG, 'link failed: init not called');
      return false;
    }
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [LocalConfigService.fileName(app)];
      const documentPicker = new picker.DocumentViewPicker(LocalConfigService.ctx);
      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return false;
      }
      const uri: string = uris[0];
      await LocalConfigService.restoreStop(app);
      await SettingsRepository.setLocalConfigUri(app, uri);
      await LocalConfigService.persistUri(uri);
      hilog.info(DOMAIN, TAG, '%{public}s config linked', app);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'link %{public}s failed: %{public}s', app, JSON.stringify(e));
      return false;
    }
  }

  /** 先恢复原文件再取消关联，避免用户手动停代理后遗留接管配置。 */
  static async unlink(app: LocalConfigApp): Promise<void> {
    await LocalConfigService.restoreStop(app);
    await SettingsRepository.setLocalConfigUri(app, '');
    await SettingsRepository.setLocalConfigBackup(app, '', false);
  }

  /** 应用启动时重新激活所有已持久化的 URI 授权。 */
  static async activatePersisted(): Promise<void> {
    await LocalConfigService.activateFor('claude');
    await LocalConfigService.activateFor('codex');
    await LocalConfigService.activateFor('opencode');
  }

  /** 接管指定渠道本地配置；重复调用不会覆盖首次保存的原始备份。 */
  static async applyStart(app: LocalConfigApp, port: number, model: string): Promise<void> {
    const uri: string = SettingsRepository.getLocalConfigUri(app);
    if (uri.length === 0) {
      return;
    }
    await LocalConfigService.ensureActivated(uri);
    try {
      const original: string = LocalConfigService.readExistingText(uri);
      if (!SettingsRepository.isLocalConfigBackupReady(app)) {
        await SettingsRepository.setLocalConfigBackup(app, original, true);
      }
      const config: string = LocalConfigService.gatewayConfig(app, port, model);
      LocalConfigService.writeText(uri, config);
      hilog.info(DOMAIN, TAG, '%{public}s config redirected to port %{public}d', app, port);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'apply %{public}s failed: %{public}s', app, JSON.stringify(e));
    }
  }

  /** 还原指定渠道的原始配置。 */
  static async restoreStop(app: LocalConfigApp): Promise<void> {
    const uri: string = SettingsRepository.getLocalConfigUri(app);
    if (uri.length === 0 || !SettingsRepository.isLocalConfigBackupReady(app)) {
      return;
    }
    await LocalConfigService.ensureActivated(uri);
    try {
      LocalConfigService.writeText(uri, SettingsRepository.getLocalConfigBackup(app));
      await SettingsRepository.setLocalConfigBackup(app, '', false);
      hilog.info(DOMAIN, TAG, '%{public}s config restored', app);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'restore %{public}s failed: %{public}s', app, JSON.stringify(e));
    }
  }

  /** 停止网关时兜底恢复所有可能被接管过的配置。 */
  static async restoreAll(): Promise<void> {
    await LocalConfigService.restoreStop('claude');
    await LocalConfigService.restoreStop('codex');
    await LocalConfigService.restoreStop('opencode');
  }

  private static fileName(app: LocalConfigApp): string {
    if (app === 'codex') {
      return 'config.toml';
    }
    if (app === 'opencode') {
      return 'opencode.json';
    }
    return 'settings.json';
  }

  private static async activateFor(app: LocalConfigApp): Promise<void> {
    const uri: string = SettingsRepository.getLocalConfigUri(app);
    if (uri.length > 0) {
      await LocalConfigService.ensureActivated(uri);
    }
  }

  private static canPersist(): boolean {
    try {
      return canIUse(CAP_FILE_SHARE);
    } catch (e) {
      return false;
    }
  }

  private static async persistUri(uri: string): Promise<void> {
    if (!LocalConfigService.canPersist()) {
      return;
    }
    try {
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      };
      await fileShare.persistPermission([policy]);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'persistPermission failed: %{public}s', JSON.stringify(e));
    }
  }

  private static async ensureActivated(uri: string): Promise<void> {
    if (!LocalConfigService.canPersist()) {
      return;
    }
    try {
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
      };
      await fileShare.activatePermission([policy]);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'activatePermission failed: %{public}s', JSON.stringify(e));
    }
  }

  private static readText(uri: string): string {
    return fs.readTextSync(uri);
  }

  /** save() 新建的空文件可能尚不可读，按空配置处理；写失败仍由外层捕获。 */
  private static readExistingText(uri: string): string {
    try {
      return LocalConfigService.readText(uri);
    } catch (e) {
      return '';
    }
  }

  private static writeText(uri: string, text: string): void {
    const file = fs.openSync(uri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    const bytes: Uint8Array = new util.TextEncoder().encode(text);
    const buffer: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    fs.writeSync(file.fd, buffer);
    fs.closeSync(file);
  }

  private static gatewayConfig(app: LocalConfigApp, port: number, model: string): string {
    const selectedModel: string = model.length > 0 ? model : DEFAULT_MODEL;
    if (app === 'codex') {
      return LocalConfigService.codexConfig(port, selectedModel);
    }
    if (app === 'opencode') {
      return LocalConfigService.openCodeConfig(port, selectedModel);
    }
    return LocalConfigService.claudeConfig(port);
  }

  private static claudeConfig(port: number): string {
    const baseUrl: string = 'http://127.0.0.1:' + port.toString();
    return '{\n' +
      '  "env": {\n' +
      '    "ANTHROPIC_BASE_URL": ' + jsonStr(baseUrl) + ',\n' +
      '    "ANTHROPIC_AUTH_TOKEN": ' + jsonStr(PLACEHOLDER_TOKEN) + '\n' +
      '  }\n' +
      '}\n';
  }

  private static codexConfig(port: number, model: string): string {
    const baseUrl: string = 'http://127.0.0.1:' + port.toString() + '/v1';
    return 'model_provider = "aigate"\n' +
      'model = ' + jsonStr(model) + '\n' +
      'model_reasoning_effort = "high"\n' +
      'disable_response_storage = true\n\n' +
      '[model_providers.aigate]\n' +
      'name = "AIGate"\n' +
      'base_url = ' + jsonStr(baseUrl) + '\n' +
      'wire_api = "responses"\n' +
      'experimental_bearer_token = ' + jsonStr(PLACEHOLDER_TOKEN) + '\n';
  }

  private static openCodeConfig(port: number, model: string): string {
    const baseUrl: string = 'http://127.0.0.1:' + port.toString() + '/v1';
    const providerModel: string = 'aigate/' + model;
    return '{\n' +
      '  "$schema": "https://opencode.ai/config.json",\n' +
      '  "model": ' + jsonStr(providerModel) + ',\n' +
      '  "provider": {\n' +
      '    "aigate": {\n' +
      '      "npm": "@ai-sdk/openai-compatible",\n' +
      '      "name": "AIGate",\n' +
      '      "options": {\n' +
      '        "baseURL": ' + jsonStr(baseUrl) + ',\n' +
      '        "apiKey": ' + jsonStr(PLACEHOLDER_TOKEN) + '\n' +
      '      },\n' +
      '      "models": {\n' +
      '        ' + jsonStr(model) + ': { "name": ' + jsonStr(model) + ' }\n' +
      '      }\n' +
      '    }\n' +
      '  }\n' +
      '}\n';
  }
}
