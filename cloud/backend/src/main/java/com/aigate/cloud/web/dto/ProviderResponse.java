package com.aigate.cloud.web.dto;

import com.aigate.cloud.domain.ChannelState;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;

public record ProviderResponse(
    String id,
    String code,
    String displayName,
    String channelCode,
    String category,
    String websiteUrl,
    String apiKeyUrl,
    String iconKey,
    String iconColor,
    boolean partner,
    boolean enabled,
    ChannelState state,
    JsonNode configuration,
    long draftVersion,
    long publishedVersion,
    Instant publishedAt,
    Instant updatedAt) {}
