/**
 * 代理服务 —— libentry.so 的薄封装（启停 / 状态 / 上游热更新）。
 * 类型定义见 types/ProxyTypes。
 */
import libentry from 'libentry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { ProxyConfig, ProxyStatus, UpstreamConfig } from '../types/ProxyTypes';

const DOMAIN = 0x0000;
const TAG = 'ProxyService';

export class ProxyService {
  // 状态缓存：getProxyStatus 失败时的回退视图
  private static currentStatus: ProxyStatus = {
    isRunning: false,
    host: '127.0.0.1',
    port: 8080,
    totalRequests: 0,
    blockedRequests: 0,
    successRequests: 0,
    failedRequests: 0,
    lastError: '',
    securityEnabled: true,
    responseSecurityEnabled: true // 与 C++ 侧默认值一致
  };

  /** 启动本地代理监听 */
  static async start(config: ProxyConfig): Promise<boolean> {
    try {
      hilog.info(DOMAIN, TAG, `Starting proxy on ${config.host}:${config.port}`);
      const result = libentry.startProxy(config);
      if (result) {
        ProxyService.currentStatus = {
          isRunning: true,
          host: config.host,
          port: config.port,
          totalRequests: 0,
          blockedRequests: 0,
          successRequests: 0,
          failedRequests: 0,
          lastError: '',
          securityEnabled: true,
          responseSecurityEnabled: true
        };
      }
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to start proxy: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /** 停止代理 */
  static stop(): void {
    try {
      hilog.info(DOMAIN, TAG, 'Stopping proxy');
      libentry.stopProxy();
      ProxyService.currentStatus.isRunning = false;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to stop proxy: ${JSON.stringify(error)}`);
    }
  }

  /** 获取代理运行状态（含统计计数） */
  static getStatus(): ProxyStatus {
    try {
      const status = libentry.getProxyStatus() as ProxyStatus;
      ProxyService.currentStatus = status;
      return status;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get status: ${JSON.stringify(error)}`);
      return ProxyService.currentStatus;
    }
  }

  /**
   * 设置/热更新上游厂商配置（baseUrl / 真实 API Key / 鉴权字段 / 模型）。
   * Claude Code 仅指向本地代理，真实 Key 由网关侧注入到转发请求。
   * 可在代理运行中调用（切换供应商时）。
   */
  static setUpstream(config: UpstreamConfig): void {
    try {
      libentry.setUpstream(config);
      hilog.info(DOMAIN, TAG,
        `upstream set: ${config.baseUrl} field=${config.apiKeyField} model=${config.model}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `setUpstream failed: ${JSON.stringify(error)}`);
    }
  }
}
