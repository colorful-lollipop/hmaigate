package com.aigate.cloud.service;

import com.aigate.cloud.domain.Channel;
import com.aigate.cloud.domain.ChannelState;
import com.aigate.cloud.domain.Provider;
import com.aigate.cloud.domain.SecurityPolicy;
import com.aigate.cloud.repository.ChannelRepository;
import com.aigate.cloud.repository.ProviderRepository;
import com.aigate.cloud.repository.SecurityPolicyRepository;
import com.aigate.cloud.web.ApiException;
import com.aigate.cloud.web.dto.DeviceChannelConfig;
import com.aigate.cloud.web.dto.DeviceConfigurationResponse;
import com.aigate.cloud.web.dto.DeviceProviderConfig;
import java.time.Instant;
import java.util.List;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeviceConfigurationService {
  private final ChannelRepository channels;
  private final ProviderRepository providers;
  private final SecurityPolicyRepository policies;
  private final ConfigurationRevisionService revisions;
  private final JsonGuard json;

  public DeviceConfigurationService(ChannelRepository channels, ProviderRepository providers,
      SecurityPolicyRepository policies, ConfigurationRevisionService revisions, JsonGuard json) {
    this.channels = channels;
    this.providers = providers;
    this.policies = policies;
    this.revisions = revisions;
    this.json = json;
  }

  @Transactional(readOnly = true)
  public DeviceConfigurationResponse current() {
    List<Channel> publishedChannels = channels.findByStateAndEnabledTrueOrderByClientTypeAscDisplayNameAsc(ChannelState.PUBLISHED);
    Set<String> channelCodes = publishedChannels.stream().map(Channel::getCode).collect(java.util.stream.Collectors.toSet());
    List<DeviceProviderConfig> publishedProviderPresets = providers
        .findByStateAndEnabledTrueOrderByChannelCodeAscDisplayNameAsc(ChannelState.PUBLISHED)
        .stream()
        .filter(provider -> channelCodes.contains(provider.getChannelCode()))
        .map(this::providerConfig)
        .toList();
    SecurityPolicy policy = policies.findFirstByOrderByCreatedAtAsc()
        .orElseThrow(() -> ApiException.notFound("默认安全策略尚未初始化"));
    return new DeviceConfigurationResponse(revisions.currentVersion(), Instant.now(),
        publishedChannels.stream().map(this::channelConfig).toList(), publishedProviderPresets,
        policy.getPublishedVersion(), json.read(policy.getPublishedJson()));
  }

  private DeviceChannelConfig channelConfig(Channel channel) {
    return new DeviceChannelConfig(channel.getCode(), channel.getDisplayName(), channel.getClientType(),
        channel.getProtocol(), channel.getIconKey(), channel.getDocumentationUrl(), channel.getLocalConfigPathHint(),
        channel.getPublishedVersion(),
        json.read(channel.getPublishedConfigJson()));
  }

  private DeviceProviderConfig providerConfig(Provider provider) {
    return new DeviceProviderConfig(provider.getCode(), provider.getDisplayName(), provider.getChannelCode(),
        provider.getCategory(), provider.getWebsiteUrl(), provider.getApiKeyUrl(), provider.getIconKey(),
        provider.getIconColor(), provider.isPartner(), provider.getPublishedVersion(),
        json.read(provider.getPublishedConfigJson()));
  }
}
