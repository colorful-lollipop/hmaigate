package com.aigate.cloud.web.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record DeviceCreateRequest(@NotBlank @Size(max = 100) String displayName) {}
