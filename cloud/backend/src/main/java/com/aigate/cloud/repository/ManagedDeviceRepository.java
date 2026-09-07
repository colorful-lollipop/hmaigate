package com.aigate.cloud.repository;

import com.aigate.cloud.domain.DeviceStatus;
import com.aigate.cloud.domain.ManagedDevice;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ManagedDeviceRepository extends JpaRepository<ManagedDevice, UUID> {
  List<ManagedDevice> findAllByOrderByCreatedAtDesc();
  long countByStatus(DeviceStatus status);
}
