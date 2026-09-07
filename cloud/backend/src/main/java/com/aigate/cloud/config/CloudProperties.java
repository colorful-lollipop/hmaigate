package com.aigate.cloud.config;

import java.util.Arrays;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "aigate")
public class CloudProperties {
  private final Admin admin = new Admin();
  private final Security security = new Security();

  public Admin getAdmin() {
    return admin;
  }

  public Security getSecurity() {
    return security;
  }

  public static class Admin {
    private String username = "admin";
    private String password = "111111";

    public String getUsername() {
      return username;
    }

    public void setUsername(String username) {
      this.username = username;
    }

    public String getPassword() {
      return password;
    }

    public void setPassword(String password) {
      this.password = password;
    }
  }

  public static class Security {
    private String allowedOrigins = "http://localhost:5173,http://127.0.0.1:5173";

    public List<String> origins() {
      return Arrays.stream(allowedOrigins.split(","))
          .map(String::trim)
          .filter(value -> !value.isEmpty())
          .toList();
    }

    public String getAllowedOrigins() {
      return allowedOrigins;
    }

    public void setAllowedOrigins(String allowedOrigins) {
      this.allowedOrigins = allowedOrigins;
    }
  }
}
