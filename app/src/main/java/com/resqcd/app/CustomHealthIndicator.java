package com.resqcd.app;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

@Component
public class CustomHealthIndicator implements HealthIndicator {

    private final Environment environment;

    @Autowired
    public CustomHealthIndicator(Environment environment) {
        this.environment = environment;
    }

    @Override
    public Health health() {
        String breakHealth = System.getenv("BREAK_HEALTH");
        if (breakHealth == null && environment != null) {
            breakHealth = environment.getProperty("BREAK_HEALTH");
        }

        if ("true".equalsIgnoreCase(breakHealth)) {
            return Health.down().withDetail("BREAK_HEALTH", "true").build();
        }
        return Health.up().build();
    }
}
