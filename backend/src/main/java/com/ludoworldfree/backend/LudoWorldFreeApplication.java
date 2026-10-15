package com.ludoworldfree.backend;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class LudoWorldFreeApplication {

    private static final Logger log = LoggerFactory.getLogger(LudoWorldFreeApplication.class);

    public static void main(String[] args) {
        SpringApplication.run(LudoWorldFreeApplication.class, args);
        log.info("🚀 [Ludo World Free Backend] Spring Boot application started successfully!");
    }
}
