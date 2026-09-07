package com.aigate.cloud.web.dto;

import com.aigate.cloud.domain.DeviceStatus;
import java.time.Instant;

public record DeviceResponse(String id, String displayName, DeviceStatus status, Instant createdAt, Instant lastSeenAt) {}
