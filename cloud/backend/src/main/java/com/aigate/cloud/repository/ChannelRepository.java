package com.aigate.cloud.repository;

import com.aigate.cloud.domain.Channel;
import com.aigate.cloud.domain.ChannelState;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ChannelRepository extends JpaRepository<Channel, UUID> {
  boolean existsByCodeIgnoreCase(String code);
  Optional<Channel> findByCodeIgnoreCase(String code);
  List<Channel> findAllByOrderByClientTypeAscDisplayNameAsc();
  List<Channel> findByStateAndEnabledTrueOrderByClientTypeAscDisplayNameAsc(ChannelState state);
}
