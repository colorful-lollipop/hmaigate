package com.aigate.cloud.service;

import com.aigate.cloud.domain.Channel;
import com.aigate.cloud.domain.ChannelState;
import com.aigate.cloud.repository.ChannelRepository;
import com.aigate.cloud.web.ApiException;
import com.aigate.cloud.web.dto.ChannelRequest;
import com.aigate.cloud.web.dto.ChannelResponse;
import java.net.URI;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ChannelService {
  private final ChannelRepository repository;
  private final ConfigurationRevisionService revisions;
  private final JsonGuard json;

  public ChannelService(ChannelRepository repository, ConfigurationRevisionService revisions, JsonGuard json) {
    this.repository = repository;
    this.revisions = revisions;
    this.json = json;
  }

  @Transactional(readOnly = true)
  public List<ChannelResponse> list() {
    return repository.findAllByOrderByClientTypeAscDisplayNameAsc().stream().map(this::response).toList();
  }

  @Transactional
  public ChannelResponse create(ChannelRequest request) {
    String code = normalizeCode(request.code());
    if (repository.existsByCodeIgnoreCase(code)) {
      throw ApiException.conflict("渠道编码已存在");
    }
    Channel channel = new Channel();
    channel.setCode(code);
    applyDraft(channel, request);
    return response(repository.save(channel));
  }

  @Transactional
  public ChannelResponse update(UUID id, ChannelRequest request) {
    Channel channel = find(id);
    if (!channel.getCode().equals(normalizeCode(request.code()))) {
      throw ApiException.badRequest("已创建渠道的 code 不可修改；请新建渠道并发布");
    }
    applyDraft(channel, request);
    channel.setDraftVersion(channel.getDraftVersion() + 1);
    return response(repository.save(channel));
  }

  @Transactional
  public ChannelResponse publish(UUID id) {
    Channel channel = find(id);
    channel.setPublishedConfigJson(channel.getDraftConfigJson());
    channel.setPublishedVersion(revisions.nextPublishedVersion());
    channel.setPublishedAt(Instant.now());
    channel.setState(ChannelState.PUBLISHED);
    channel.setUpdatedAt(Instant.now());
    return response(repository.save(channel));
  }

  @Transactional
  public ChannelResponse archive(UUID id) {
    Channel channel = find(id);
    channel.setState(ChannelState.ARCHIVED);
    channel.setEnabled(false);
    channel.setUpdatedAt(Instant.now());
    revisions.nextPublishedVersion();
    return response(repository.save(channel));
  }

  private Channel find(UUID id) {
    return repository.findById(id).orElseThrow(() -> ApiException.notFound("渠道不存在"));
  }

  private void applyDraft(Channel channel, ChannelRequest request) {
    json.requireChannelConfiguration(request.configuration());
    validateUrl(request.documentationUrl(), "documentationUrl");
    channel.setDisplayName(request.displayName().trim());
    channel.setClientType(normalizeCode(request.clientType()));
    channel.setProtocol(normalizeCode(request.protocol()));
    channel.setIconKey(normalizeCode(request.iconKey()));
    channel.setDocumentationUrl(blankToNull(request.documentationUrl()));
    channel.setLocalConfigPathHint(blankToNull(request.localConfigPathHint()));
    channel.setEnabled(request.enabled());
    channel.setDraftConfigJson(json.write(request.configuration()));
    channel.setUpdatedAt(Instant.now());
  }

  private ChannelResponse response(Channel channel) {
    return new ChannelResponse(channel.getId().toString(), channel.getCode(), channel.getDisplayName(),
        channel.getClientType(), channel.getProtocol(), channel.getIconKey(), channel.getDocumentationUrl(),
        channel.getLocalConfigPathHint(),
        channel.isEnabled(), channel.getState(), json.read(channel.getDraftConfigJson()), channel.getDraftVersion(),
        channel.getPublishedVersion(), channel.getPublishedAt(), channel.getUpdatedAt());
  }

  static String normalizeCode(String value) {
    return value.trim().toLowerCase(Locale.ROOT);
  }

  static String blankToNull(String value) {
    return value == null || value.isBlank() ? null : value.trim();
  }

  static void validateUrl(String value, String fieldName) {
    if (value == null || value.isBlank()) {
      return;
    }
    try {
      URI uri = URI.create(value);
      if (!"https".equalsIgnoreCase(uri.getScheme()) && !"http".equalsIgnoreCase(uri.getScheme())) {
        throw ApiException.badRequest(fieldName + " 只允许 http 或 https URL");
      }
    } catch (IllegalArgumentException exception) {
      throw ApiException.badRequest(fieldName + " 不是合法 URL");
    }
  }
}
