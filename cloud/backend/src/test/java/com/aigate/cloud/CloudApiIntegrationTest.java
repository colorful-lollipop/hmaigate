package com.aigate.cloud;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.aigate.cloud.web.dto.ProviderRequest;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
    "spring.datasource.url=jdbc:sqlite:target/aigate-cloud-integration.db",
    "spring.jpa.hibernate.ddl-auto=create-drop",
    "aigate.admin.password=integration-password"
})
class CloudApiIntegrationTest {
  @Autowired
  private MockMvc mvc;

  @Autowired
  private ObjectMapper objectMapper;

  @Test
  void publishesProviderPresetAndDeliversOnlyPublishedConfigurationToDevice() throws Exception {
    mvc.perform(options("/api/v1/admin/overview")
            .header("Origin", "http://127.0.0.1:5173")
            .header("Access-Control-Request-Method", "GET"))
        .andExpect(status().isOk())
        .andExpect(header().string("Access-Control-Allow-Origin", "http://127.0.0.1:5173"));

    mvc.perform(get("/actuator/health"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.status").value("UP"));

    String channelId = createChannel();
    mvc.perform(post("/api/v1/admin/channels/{id}/publish", channelId).with(httpBasic("admin", "integration-password")))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.state").value("PUBLISHED"));

    String providerId = createProvider();
    mvc.perform(post("/api/v1/admin/providers/{id}/publish", providerId).with(httpBasic("admin", "integration-password")))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.state").value("PUBLISHED"));

    MvcResult issued = mvc.perform(post("/api/v1/admin/devices")
            .with(httpBasic("admin", "integration-password"))
            .contentType(MediaType.APPLICATION_JSON)
            .content("{\"displayName\":\"integration-device\"}"))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.deviceKey").isString())
        .andReturn();
    String deviceKey = read(issued).path("deviceKey").asText();
    assertThat(deviceKey).startsWith("agdk_");

    MvcResult configuration = mvc.perform(get("/api/v1/device/config")
            .header("X-AIGate-Device-Key", deviceKey))
        .andExpect(status().isOk())
        .andExpect(header().exists("ETag"))
        .andExpect(jsonPath("$.providerPresets[0].code").value("glm"))
        .andExpect(jsonPath("$.providerPresets[0].configuration.settingsTemplate.env.ANTHROPIC_AUTH_TOKEN")
            .value("{{apiKey}}"))
        .andReturn();
    JsonNode snapshot = read(configuration);
    assertThat(snapshot.path("providers").isMissingNode()).isTrue();
    assertThat(snapshot.path("providerPresets").isArray()).isTrue();
    assertThat(containsChannel(snapshot, "codex")).isTrue();
    assertThat(containsChannel(snapshot, "opencode")).isTrue();
    String eTag = configuration.getResponse().getHeader("ETag");

    mvc.perform(get("/api/v1/device/config")
            .header("X-AIGate-Device-Key", deviceKey)
            .header("If-None-Match", eTag))
        .andExpect(status().isNotModified())
        .andExpect(header().string("ETag", eTag));

    String invalidProvider = """
        {"code":"unsafe-provider","displayName":"Unsafe","channelCode":"claude","category":"third_party",
        "iconKey":"server","enabled":true,"partner":false,
        "configuration":{"settingsTemplate":{"env":{"ANTHROPIC_AUTH_TOKEN":"sk-this-is-not-allowed-123456789"}}}}
        """;
    mvc.perform(post("/api/v1/admin/providers")
            .with(httpBasic("admin", "integration-password"))
            .contentType(MediaType.APPLICATION_JSON)
            .content(invalidProvider))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.code").value("bad_request"));
  }

  private String createChannel() throws Exception {
    String channel = """
        {"code":"integration-claude","displayName":"Integration Claude","clientType":"integration-claude","protocol":"anthropic",
        "iconKey":"plug","enabled":true,
        "configuration":{"schemaVersion":1,"configurationFormat":"settings-json-env",
        "fieldMap":{"baseUrlField":"ANTHROPIC_BASE_URL","apiKeyField":"ANTHROPIC_AUTH_TOKEN","modelField":"ANTHROPIC_MODEL"}}}
        """;
    MvcResult result = mvc.perform(post("/api/v1/admin/channels")
            .with(httpBasic("admin", "integration-password"))
            .contentType(MediaType.APPLICATION_JSON)
            .content(channel))
        .andExpect(status().isCreated())
        .andReturn();
    return read(result).path("id").asText();
  }

  private String createProvider() throws Exception {
    String provider = """
        {"code":"glm","displayName":"Zhipu GLM","channelCode":"integration-claude","category":"cn_official",
        "websiteUrl":"https://open.bigmodel.cn","iconKey":"server","enabled":true,"partner":false,
        "configuration":{"schemaVersion":1,"settingsTemplate":{"env":{
        "ANTHROPIC_BASE_URL":"{{baseUrl}}","ANTHROPIC_AUTH_TOKEN":"{{apiKey}}","ANTHROPIC_MODEL":"{{model}}"}},
        "endpointCandidates":["https://open.bigmodel.cn/api/anthropic"],"defaultModel":"glm-5.1"}}
        """;
    objectMapper.readValue(provider, ProviderRequest.class);
    MvcResult result = mvc.perform(post("/api/v1/admin/providers")
            .with(httpBasic("admin", "integration-password"))
            .contentType(MediaType.APPLICATION_JSON)
            .content(provider))
        .andExpect(status().isCreated())
        .andReturn();
    return read(result).path("id").asText();
  }

  private JsonNode read(MvcResult result) throws Exception {
    return objectMapper.readTree(result.getResponse().getContentAsString());
  }

  private boolean containsChannel(JsonNode snapshot, String code) {
    for (JsonNode channel : snapshot.path("channels")) {
      if (code.equals(channel.path("code").asText())) {
        return true;
      }
    }
    return false;
  }
}
