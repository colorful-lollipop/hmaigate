package com.aigate.cloud.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import java.time.Instant;
import java.util.UUID;

@Entity
public class SecurityPolicy {
  @Id
  @GeneratedValue
  private UUID id;

  @Lob
  @Column(nullable = false)
  private String draftJson;

  @Lob
  @Column(nullable = false)
  private String publishedJson;

  @Column(nullable = false)
  private long draftVersion = 1;

  private long publishedVersion;
  private Instant publishedAt;
  @Column(nullable = false)
  private Instant createdAt = Instant.now();
  @Column(nullable = false)
  private Instant updatedAt = Instant.now();

  public UUID getId() { return id; }
  public String getDraftJson() { return draftJson; }
  public void setDraftJson(String draftJson) { this.draftJson = draftJson; }
  public String getPublishedJson() { return publishedJson; }
  public void setPublishedJson(String publishedJson) { this.publishedJson = publishedJson; }
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
