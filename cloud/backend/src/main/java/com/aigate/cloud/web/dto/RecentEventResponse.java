package com.aigate.cloud.web.dto;

import java.time.Instant;

public record RecentEventResponse(
    String id,
    String deviceId,
    String eventType,
    String severity,
    String channelCode,
    String ruleId,
    Instant occurredAt,
    Instant receivedAt) {}
