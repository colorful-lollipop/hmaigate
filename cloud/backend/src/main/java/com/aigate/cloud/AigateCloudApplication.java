package com.aigate.cloud;

import com.aigate.cloud.config.CloudProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;

@SpringBootApplication
@EnableConfigurationProperties(CloudProperties.class)
public class AigateCloudApplication {
  public static void main(String[] args) {
    SpringApplication.run(AigateCloudApplication.class, args);
  }
}
