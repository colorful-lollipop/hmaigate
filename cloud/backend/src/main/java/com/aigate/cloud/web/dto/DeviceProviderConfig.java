package com.aigate.cloud.web.dto;

import com.fasterxml.jackson.databind.JsonNode;

/** 设备侧供应商预设。configuration 仅允许有 {{apiKey}} 等占位符。 */
public record DeviceProviderConfig(
    String code,
    String displayName,
    String channelCode,
    String category,
    String websiteUrl,
    String apiKeyUrl,
    String iconKey,
    String iconColor,
    boolean partner,
    long revision,
    JsonNode configuration) {}
