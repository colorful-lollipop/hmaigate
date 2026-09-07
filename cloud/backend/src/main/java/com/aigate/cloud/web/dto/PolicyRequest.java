package com.aigate.cloud.web.dto;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.validation.constraints.NotNull;

public record PolicyRequest(@NotNull JsonNode policy) {}
