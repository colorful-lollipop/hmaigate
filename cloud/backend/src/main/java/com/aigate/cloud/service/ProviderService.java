package com.aigate.cloud.service;

import com.aigate.cloud.domain.Channel;
import com.aigate.cloud.domain.ChannelState;
import com.aigate.cloud.domain.Provider;
import com.aigate.cloud.repository.ChannelRepository;
import com.aigate.cloud.repository.ProviderRepository;
import com.aigate.cloud.web.ApiException;
import com.aigate.cloud.web.dto.ProviderRequest;
import com.aigate.cloud.web.dto.ProviderResponse;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProviderService {
  private final ProviderRepository repository;
  private final ChannelRepository channelRepository;
  private final ConfigurationRevisionService revisions;
  private final JsonGuard json;

  public ProviderService(ProviderRepository repository, ChannelRepository channelRepository,
      ConfigurationRevisionService revisions, JsonGuard json) {
    this.repository = repository;
    this.channelRepository = channelRepository;
    this.revisions = revisions;
    this.json = json;
  }

  @Transactional(readOnly = true)
  public List<ProviderResponse> list() {
    return repository.findAllByOrderByChannelCodeAscDisplayNameAsc().stream().map(this::response).toList();
  }

  @Transactional
  public ProviderResponse create(ProviderRequest request) {
    String code = ChannelService.normalizeCode(request.code());
    if (repository.existsByCodeIgnoreCase(code)) {
      throw ApiException.conflict("供应商编码已存在");
    }
    Provider provider = new Provider();
    provider.setCode(code);
    applyDraft(provider, request);
    return response(repository.save(provider));
  }

  @Transactional
  public ProviderResponse update(UUID id, ProviderRequest request) {
    Provider provider = find(id);
    if (!provider.getCode().equals(ChannelService.normalizeCode(request.code()))) {
      throw ApiException.badRequest("已创建供应商的 code 不可修改；请新建供应商并发布");
    }
    applyDraft(provider, request);
    provider.setDraftVersion(provider.getDraftVersion() + 1);
    return response(repository.save(provider));
  }

  @Transactional
  public ProviderResponse publish(UUID id) {
    Provider provider = find(id);
    Channel channel = channelRepository.findByCodeIgnoreCase(provider.getChannelCode())
        .orElseThrow(() -> ApiException.badRequest("供应商所属渠道不存在"));
    if (channel.getState() != ChannelState.PUBLISHED || !channel.isEnabled()) {
      throw ApiException.badRequest("请先发布并启用供应商所属渠道");
    }
    provider.setPublishedConfigJson(provider.getDraftConfigJson());
    provider.setPublishedVersion(revisions.nextPublishedVersion());
    provider.setPublishedAt(Instant.now());
    provider.setState(ChannelState.PUBLISHED);
    provider.setUpdatedAt(Instant.now());
    return response(repository.save(provider));
  }

  @Transactional
  public ProviderResponse archive(UUID id) {
    Provider provider = find(id);
    provider.setState(ChannelState.ARCHIVED);
    provider.setEnabled(false);
    provider.setUpdatedAt(Instant.now());
    revisions.nextPublishedVersion();
    return response(repository.save(provider));
  }

  private Provider find(UUID id) {
    return repository.findById(id).orElseThrow(() -> ApiException.notFound("供应商不存在"));
  }

  private void applyDraft(Provider provider, ProviderRequest request) {
    String channelCode = ChannelService.normalizeCode(request.channelCode());
    if (!channelRepository.existsByCodeIgnoreCase(channelCode)) {
      throw ApiException.badRequest("供应商所属渠道不存在");
    }
    json.requireProviderConfiguration(request.configuration());
    ChannelService.validateUrl(request.websiteUrl(), "websiteUrl");
    ChannelService.validateUrl(request.apiKeyUrl(), "apiKeyUrl");
    provider.setDisplayName(request.displayName().trim());
    provider.setChannelCode(channelCode);
    provider.setCategory(ChannelService.normalizeCode(request.category()));
    provider.setWebsiteUrl(ChannelService.blankToNull(request.websiteUrl()));
    provider.setApiKeyUrl(ChannelService.blankToNull(request.apiKeyUrl()));
    provider.setIconKey(ChannelService.normalizeCode(request.iconKey()));
    provider.setIconColor(ChannelService.blankToNull(request.iconColor()));
    provider.setPartner(request.partner());
    provider.setEnabled(request.enabled());
    provider.setDraftConfigJson(json.write(request.configuration()));
    provider.setUpdatedAt(Instant.now());
  }

  private ProviderResponse response(Provider provider) {
    return new ProviderResponse(provider.getId().toString(), provider.getCode(), provider.getDisplayName(),
        provider.getChannelCode(), provider.getCategory(), provider.getWebsiteUrl(), provider.getApiKeyUrl(),
        provider.getIconKey(), provider.getIconColor(), provider.isPartner(), provider.isEnabled(), provider.getState(),
        json.read(provider.getDraftConfigJson()), provider.getDraftVersion(), provider.getPublishedVersion(),
        provider.getPublishedAt(), provider.getUpdatedAt());
  }
}
