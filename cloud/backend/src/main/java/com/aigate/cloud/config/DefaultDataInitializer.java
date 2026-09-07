package com.aigate.cloud.config;

import com.aigate.cloud.domain.ConfigurationRevision;
import com.aigate.cloud.domain.Channel;
import com.aigate.cloud.domain.ChannelState;
import com.aigate.cloud.domain.SecurityPolicy;
import com.aigate.cloud.repository.ChannelRepository;
import com.aigate.cloud.repository.ConfigurationRevisionRepository;
import com.aigate.cloud.repository.SecurityPolicyRepository;
import com.aigate.cloud.service.SecurityPolicyService;
import java.time.Instant;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class DefaultDataInitializer {
  @Bean
  ApplicationRunner initializeData(ConfigurationRevisionRepository revisions, SecurityPolicyRepository policies,
      ChannelRepository channels) {
    return args -> {
      if (!revisions.existsById(1)) {
        revisions.save(new ConfigurationRevision());
      }
      if (policies.findFirstByOrderByCreatedAtAsc().isEmpty()) {
        SecurityPolicy policy = new SecurityPolicy();
        policy.setDraftJson(SecurityPolicyService.DEFAULT_POLICY);
        policy.setPublishedJson(SecurityPolicyService.DEFAULT_POLICY);
        policy.setPublishedVersion(1);
        policy.setPublishedAt(Instant.now());
        policies.save(policy);
      }
      ConfigurationRevision revision = revisions.findById(1).orElseThrow();
      long nextVersion = revision.getCurrentVersion();
      nextVersion = ensureChannel(channels, nextVersion, "claude", "Claude Code", "claude", "anthropic",
          "plug", "https://docs.anthropic.com/en/docs/claude-code", "~/.claude/settings.json",
          "{\"schemaVersion\":1,\"configurationFormat\":\"settings-json-env\",\"fieldMap\":{\"baseUrlField\":\"ANTHROPIC_BASE_URL\",\"apiKeyField\":\"ANTHROPIC_AUTH_TOKEN\",\"modelField\":\"ANTHROPIC_MODEL\"}}");
      nextVersion = ensureChannel(channels, nextVersion, "codex", "Codex", "codex", "openai",
          "openai", "https://developers.openai.com/codex/config-reference", "~/.codex/config.toml",
          "{\"schemaVersion\":1,\"configurationFormat\":\"config-toml\",\"fieldMap\":{\"baseUrlField\":\"config.base_url\",\"apiKeyField\":\"OPENAI_API_KEY\",\"modelField\":\"config.model\"}}");
      nextVersion = ensureChannel(channels, nextVersion, "opencode", "OpenCode", "opencode", "openai",
          "opencode", "https://opencode.ai/docs/config", "~/.config/opencode/opencode.json",
          "{\"schemaVersion\":1,\"configurationFormat\":\"openai-compatible-json\",\"fieldMap\":{\"baseUrlField\":\"OPENAI_BASE_URL\",\"apiKeyField\":\"OPENAI_API_KEY\",\"modelField\":\"OPENAI_MODEL\"}}");
      if (nextVersion != revision.getCurrentVersion()) {
        revision.setCurrentVersion(nextVersion);
        revisions.save(revision);
      }
    };
  }

  private long ensureChannel(ChannelRepository channels, long currentVersion, String code, String displayName,
      String clientType, String protocol, String iconKey, String documentationUrl, String localConfigPathHint,
      String configuration) {
    if (channels.existsByCodeIgnoreCase(code)) {
      return currentVersion;
    }
    Channel channel = new Channel();
    channel.setCode(code);
    channel.setDisplayName(displayName);
    channel.setClientType(clientType);
    channel.setProtocol(protocol);
    channel.setIconKey(iconKey);
    channel.setDocumentationUrl(documentationUrl);
    channel.setLocalConfigPathHint(localConfigPathHint);
    channel.setEnabled(true);
    channel.setState(ChannelState.PUBLISHED);
    channel.setDraftConfigJson(configuration);
    channel.setPublishedConfigJson(configuration);
    channel.setPublishedVersion(currentVersion + 1);
    channel.setPublishedAt(Instant.now());
    channels.save(channel);
    return currentVersion + 1;
  }
}
