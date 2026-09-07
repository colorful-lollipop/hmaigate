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

@Entity
@Table(name = "channels", uniqueConstraints = @UniqueConstraint(name = "uk_channel_code", columnNames = "code"))
public class Channel {
  @Id
  @GeneratedValue
  private UUID id;

  @Column(nullable = false, length = 50)
  private String code;

  @Column(nullable = false, length = 100)
  private String displayName;

  @Column(nullable = false, length = 50)
  private String clientType;

  @Column(nullable = false, length = 50)
  private String protocol;

  @Column(nullable = false, length = 80)
  private String iconKey = "plug";

  @Column(length = 500)
  private String documentationUrl;

  /**
   * 客户端本地配置文件的常见位置，仅用于端侧 picker 的展示提示。
   * 云端不能也不会按该路径直接读写沙箱外文件。
   */
  @Column(length = 500)
  private String localConfigPathHint;

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
  public String getClientType() { return clientType; }
  public void setClientType(String clientType) { this.clientType = clientType; }
  public String getProtocol() { return protocol; }
  public void setProtocol(String protocol) { this.protocol = protocol; }
  public String getIconKey() { return iconKey; }
  public void setIconKey(String iconKey) { this.iconKey = iconKey; }
  public String getDocumentationUrl() { return documentationUrl; }
  public void setDocumentationUrl(String documentationUrl) { this.documentationUrl = documentationUrl; }
  public String getLocalConfigPathHint() { return localConfigPathHint; }
  public void setLocalConfigPathHint(String localConfigPathHint) { this.localConfigPathHint = localConfigPathHint; }
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
