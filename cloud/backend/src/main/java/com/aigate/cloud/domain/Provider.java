package com.aigate.cloud.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.Instant;
import java.util.UUID;

/**
 * 运营侧供应商预设。配置中只能出现占位符，不保存终端用户的真实 API Key。
 */
@Entity
@Table(name = "providers", uniqueConstraints = @UniqueConstraint(name = "uk_provider_code", columnNames = "code"))
public class Provider {
  @Id
  @GeneratedValue
  private UUID id;

  @Column(nullable = false, length = 50)
  private String code;

  @Column(nullable = false, length = 100)
  private String displayName;

  @Column(nullable = false, length = 50)
  private String channelCode;

  @Column(nullable = false, length = 40)
  private String category = "third_party";

  @Column(length = 500)
  private String websiteUrl;

  @Column(length = 500)
  private String apiKeyUrl;

  @Column(nullable = false, length = 80)
  private String iconKey = "server";

  @Column(length = 9)
  private String iconColor;

  @Column(nullable = false)
  private boolean partner;

  @Column(nullable = false)
  private boolean enabled = true;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 20)
  private ChannelState state = ChannelState.DRAFT;

  @Lob
  @Column(nullable = false)
  private String draftConfigJson = "{}";

  @Lob
  private String publishedConfigJson;

  @Column(nullable = false)
  private long draftVersion = 1;
  private long publishedVersion;
  private Instant publishedAt;
  @Column(nullable = false)
  private Instant createdAt = Instant.now();
  @Column(nullable = false)
  private Instant updatedAt = Instant.now();

  public UUID getId() { return id; }
  public String getCode() { return code; }
  public void setCode(String code) { this.code = code; }
  public String getDisplayName() { return displayName; }
  public void setDisplayName(String displayName) { this.displayName = displayName; }
  public String getChannelCode() { return channelCode; }
  public void setChannelCode(String channelCode) { this.channelCode = channelCode; }
  public String getCategory() { return category; }
  public void setCategory(String category) { this.category = category; }
  public String getWebsiteUrl() { return websiteUrl; }
  public void setWebsiteUrl(String websiteUrl) { this.websiteUrl = websiteUrl; }
  public String getApiKeyUrl() { return apiKeyUrl; }
  public void setApiKeyUrl(String apiKeyUrl) { this.apiKeyUrl = apiKeyUrl; }
  public String getIconKey() { return iconKey; }
  public void setIconKey(String iconKey) { this.iconKey = iconKey; }
  public String getIconColor() { return iconColor; }
  public void setIconColor(String iconColor) { this.iconColor = iconColor; }
  public boolean isPartner() { return partner; }
  public void setPartner(boolean partner) { this.partner = partner; }
  public boolean isEnabled() { return enabled; }
  public void setEnabled(boolean enabled) { this.enabled = enabled; }
  public ChannelState getState() { return state; }
  public void setState(ChannelState state) { this.state = state; }
  public String getDraftConfigJson() { return draftConfigJson; }
  public void setDraftConfigJson(String draftConfigJson) { this.draftConfigJson = draftConfigJson; }
  public String getPublishedConfigJson() { return publishedConfigJson; }
  public void setPublishedConfigJson(String publishedConfigJson) { this.publishedConfigJson = publishedConfigJson; }
  public long getDraftVersion() { return draftVersion; }
  public void setDraftVersion(long draftVersion) { this.draftVersion = draftVersion; }
  public long getPublishedVersion() { return publishedVersion; }
  public void setPublishedVersion(long publishedVersion) { this.publishedVersion = publishedVersion; }
  public Instant getPublishedAt() { return publishedAt; }
  public void setPublishedAt(Instant publishedAt) { this.publishedAt = publishedAt; }
  public Instant getCreatedAt() { return createdAt; }
  public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
  public Instant getUpdatedAt() { return updatedAt; }
  public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
