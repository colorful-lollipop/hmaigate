package com.aigate.cloud.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import java.time.Instant;
import java.util.UUID;

@Entity
public class ManagedDevice {
  @Id
  @GeneratedValue
  private UUID id;

  @Column(nullable = false, length = 100)
  private String displayName;

  @Column(nullable = false, length = 100)
  private String keyHash;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false, length = 20)
  private DeviceStatus status = DeviceStatus.ACTIVE;

  @Column(nullable = false)
  private Instant createdAt = Instant.now();
  private Instant lastSeenAt;

  public UUID getId() { return id; }
  public String getDisplayName() { return displayName; }
  public void setDisplayName(String displayName) { this.displayName = displayName; }
  public String getKeyHash() { return keyHash; }
  public void setKeyHash(String keyHash) { this.keyHash = keyHash; }
  public DeviceStatus getStatus() { return status; }
  public void setStatus(DeviceStatus status) { this.status = status; }
  public Instant getCreatedAt() { return createdAt; }
  public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
  public Instant getLastSeenAt() { return lastSeenAt; }
  public void setLastSeenAt(Instant lastSeenAt) { this.lastSeenAt = lastSeenAt; }
}
