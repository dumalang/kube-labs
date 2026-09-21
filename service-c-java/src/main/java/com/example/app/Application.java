package com.example.app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Instant;
import java.util.List;
import java.util.Map;

@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}

@RestController
@RequestMapping("/api/v1/java")
class ApiController {

    @GetMapping("/users")
    public Map<String, Object> getUsers() {
        String hostname;
        try {
            hostname = InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            hostname = "unknown-host";
        }

        String appEnv = System.getenv().getOrDefault("APP_ENV", "development");

        return Map.of(
            "service", "service-c-java",
            "language", "Java 21",
            "framework", "Spring Boot 3",
            "hostname", hostname,
            "environment", appEnv,
            "users", List.of(
                Map.of("id", 1, "name", "Alice Johnson", "role", "DevOps Engineer"),
                Map.of("id", 2, "name", "Bob Smith", "role", "Kubernetes Administrator"),
                Map.of("id", 3, "name", "Charlie Brown", "role", "Cloud Architect")
            ),
            "timestamp", Instant.now().toString()
        );
    }

    @GetMapping("/healthz")
    public Map<String, String> healthz() {
        return Map.of("status", "HEALTHY", "timestamp", Instant.now().toString());
    }

    @GetMapping("/readyz")
    public Map<String, String> readyz() {
        return Map.of("status", "READY");
    }
}
