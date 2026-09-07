package com.aigate.cloud.web.dto;

import com.fasterxml.jackson.databind.JsonNode;

/** 设备侧仅获取已发布渠道的公开配置，不含草稿和凭据。 */
public record DeviceChannelConfig(
    String code,
    String displayName,
    String clientType,
    String protocol,
    String iconKey,
    String documentationUrl,
    String localConfigPathHint,
    long revision,
    JsonNode configuration) {}
