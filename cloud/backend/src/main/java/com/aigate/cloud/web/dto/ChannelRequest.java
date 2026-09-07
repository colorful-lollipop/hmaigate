package com.aigate.cloud.web.dto;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record ChannelRequest(
    @NotBlank @Pattern(regexp = "^[a-z][a-z0-9-]{0,48}$", message = "必须为小写字母开头的渠道编码") String code,
    @NotBlank @Size(max = 100) String displayName,
    @NotBlank @Pattern(regexp = "^[a-z][a-z0-9-]{0,48}$", message = "格式不合法") String clientType,
    @NotBlank @Pattern(regexp = "^[a-z][a-z0-9_-]{0,48}$", message = "格式不合法") String protocol,
    @NotBlank @Pattern(regexp = "^[a-z][a-z0-9-]{0,78}$", message = "格式不合法") String iconKey,
    @Size(max = 500) String documentationUrl,
    @Size(max = 500) String localConfigPathHint,
    boolean enabled,
    @NotNull JsonNode configuration) {}
