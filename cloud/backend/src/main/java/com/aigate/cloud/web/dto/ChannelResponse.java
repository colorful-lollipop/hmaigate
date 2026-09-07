package com.aigate.cloud.web.dto;

import com.aigate.cloud.domain.ChannelState;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;

public record ChannelResponse(
    String id,
    String code,
    String displayName,
    String clientType,
    String protocol,
    String iconKey,
    String documentationUrl,
    String localConfigPathHint,
    boolean enabled,
    ChannelState state,
    JsonNode configuration,
    long draftVersion,
    long publishedVersion,
    Instant publishedAt,
    Instant updatedAt) {}
