package com.aigate.cloud.web.dto;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;

public record TelemetryRequest(
    @NotBlank @Pattern(regexp = "^[A-Z][A-Z0-9_]{1,62}$", message = "必须为大写事件类型") String eventType,
    @NotBlank @Pattern(regexp = "^(INFO|WARN|BLOCK|ERROR)$", message = "必须为 INFO、WARN、BLOCK 或 ERROR") String severity,
    @Size(max = 64) String channelCode,
    @Size(max = 100) String ruleId,
    Instant occurredAt,
    JsonNode attributes) {}
