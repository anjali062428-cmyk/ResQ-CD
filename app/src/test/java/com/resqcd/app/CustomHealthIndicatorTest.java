package com.resqcd.app;

import org.junit.jupiter.api.Test;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.Status;
import org.springframework.mock.env.MockEnvironment;

import static org.junit.jupiter.api.Assertions.assertEquals;

public class CustomHealthIndicatorTest {

    @Test
    public void testHealthUpByDefault() {
        MockEnvironment env = new MockEnvironment();
        CustomHealthIndicator indicator = new CustomHealthIndicator(env);

        Health health = indicator.health();
        assertEquals(Status.UP, health.getStatus());
    }

    @Test
    public void testHealthDownWhenBreakHealthIsTrue() {
        MockEnvironment env = new MockEnvironment();
        env.setProperty("BREAK_HEALTH", "true");
        CustomHealthIndicator indicator = new CustomHealthIndicator(env);

        Health health = indicator.health();
        assertEquals(Status.DOWN, health.getStatus());
    }
}
