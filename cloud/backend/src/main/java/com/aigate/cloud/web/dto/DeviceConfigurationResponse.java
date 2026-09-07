package com.aigate.cloud.web.dto;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.util.List;

public record DeviceConfigurationResponse(
    long configVersion,
    Instant generatedAt,
    List<DeviceChannelConfig> channels,
    List<DeviceProviderConfig> providerPresets,
    long securityPolicyVersion,
    JsonNode securityPolicy) {}
