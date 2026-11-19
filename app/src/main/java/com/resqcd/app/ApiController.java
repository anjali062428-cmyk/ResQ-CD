package com.resqcd.app;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ApiController {

    private final Environment environment;

    @Autowired
    public ApiController(Environment environment) {
        this.environment = environment;
    }

    @GetMapping("/api/hello")
    public String hello() {
        return "Hello, World!";
    }

    @GetMapping("/api/version")
    public String version() {
        String envVersion = System.getenv("APP_VERSION");
        if (envVersion != null && !envVersion.isBlank()) {
            return envVersion;
        }
        if (environment != null) {
            String propVersion = environment.getProperty("APP_VERSION");
            if (propVersion != null && !propVersion.isBlank()) {
                return propVersion;
            }
        }
        return "unknown";
    }
}
