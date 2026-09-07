package com.aigate.cloud.service;

import com.aigate.cloud.domain.DeviceStatus;
import com.aigate.cloud.domain.ManagedDevice;
import com.aigate.cloud.repository.ManagedDeviceRepository;
import com.aigate.cloud.web.ApiException;
import com.aigate.cloud.web.dto.DeviceIssueResponse;
import com.aigate.cloud.web.dto.DeviceResponse;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.List;
import java.util.UUID;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeviceKeyService {
  private static final SecureRandom RANDOM = new SecureRandom();
  private final ManagedDeviceRepository repository;
  private final PasswordEncoder encoder;

  public DeviceKeyService(ManagedDeviceRepository repository, PasswordEncoder encoder) {
    this.repository = repository;
    this.encoder = encoder;
  }

  @Transactional(readOnly = true)
  public List<DeviceResponse> list() {
    return repository.findAllByOrderByCreatedAtDesc().stream().map(this::response).toList();
  }

  @Transactional
  public DeviceIssueResponse create(String displayName) {
    ManagedDevice device = new ManagedDevice();
    device.setDisplayName(displayName.trim());
    // UUID 由 Hibernate 在插入时生成；先写入无法匹配任何设备密钥的占位值，随后同一事务内替换。
    device.setKeyHash("pending-key-issuance");
    device = repository.saveAndFlush(device);
    String key = issueKey(device);
    return new DeviceIssueResponse(response(device), key);
  }

  @Transactional
  public DeviceIssueResponse rotate(UUID id) {
    ManagedDevice device = find(id);
    if (device.getStatus() == DeviceStatus.REVOKED) {
      throw ApiException.badRequest("已撤销设备不能轮换密钥");
    }
    String key = issueKey(device);
    return new DeviceIssueResponse(response(device), key);
  }

  @Transactional
  public DeviceResponse revoke(UUID id) {
    ManagedDevice device = find(id);
    device.setStatus(DeviceStatus.REVOKED);
    return response(repository.save(device));
  }

  @Transactional
  public ManagedDevice authenticate(String rawKey) {
    if (rawKey == null || rawKey.isBlank()) {
      throw ApiException.forbidden("缺少设备密钥");
    }
    String[] parts = rawKey.split("_", 3);
    if (parts.length != 3 || !"agdk".equals(parts[0])) {
      throw ApiException.forbidden("设备密钥格式不正确");
    }
    try {
      ManagedDevice device = repository.findById(UUID.fromString(parts[1]))
          .orElseThrow(() -> ApiException.forbidden("设备密钥无效"));
      if (device.getStatus() != DeviceStatus.ACTIVE || !encoder.matches(rawKey, device.getKeyHash())) {
        throw ApiException.forbidden("设备密钥无效或已撤销");
      }
      device.setLastSeenAt(Instant.now());
      return device;
    } catch (IllegalArgumentException exception) {
      throw ApiException.forbidden("设备密钥格式不正确");
    }
  }

  private ManagedDevice find(UUID id) {
    return repository.findById(id).orElseThrow(() -> ApiException.notFound("设备不存在"));
  }

  private String issueKey(ManagedDevice device) {
    byte[] randomBytes = new byte[32];
    RANDOM.nextBytes(randomBytes);
    String random = Base64.getUrlEncoder().withoutPadding().encodeToString(randomBytes);
    String raw = "agdk_" + device.getId() + "_" + random;
    device.setKeyHash(encoder.encode(raw));
    repository.save(device);
    return raw;
  }

  private DeviceResponse response(ManagedDevice device) {
    return new DeviceResponse(device.getId().toString(), device.getDisplayName(), device.getStatus(),
        device.getCreatedAt(), device.getLastSeenAt());
  }
}
