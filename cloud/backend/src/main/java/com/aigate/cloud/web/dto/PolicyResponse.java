package com.aigate.cloud.web.dto;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;

public record PolicyResponse(
    JsonNode policy,
    long draftVersion,
    long publishedVersion,
    Instant publishedAt,
    Instant updatedAt) {}
