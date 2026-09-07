package com.aigate.cloud.web.dto;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record ProviderRequest(
    @NotBlank @Pattern(regexp = "^[a-z][a-z0-9-]{0,48}$", message = "必须为小写字母开头的供应商编码") String code,
    @NotBlank @Size(max = 100) String displayName,
    @NotBlank @Pattern(regexp = "^[a-z][a-z0-9-]{0,48}$", message = "格式不合法") String channelCode,
    @NotBlank @Pattern(regexp = "^[a-z][a-z0-9_-]{0,38}$", message = "格式不合法") String category,
    @Size(max = 500) String websiteUrl,
    @Size(max = 500) String apiKeyUrl,
    @NotBlank @Pattern(regexp = "^[a-z][a-z0-9-]{0,78}$", message = "格式不合法") String iconKey,
    @Pattern(regexp = "^$|^#[0-9A-Fa-f]{6}$", message = "必须为 #RRGGBB") String iconColor,
    boolean partner,
    boolean enabled,
    @NotNull JsonNode configuration) {}
