package com.ludoworldfree.backend.controller;

import org.springframework.http.HttpStatusCode;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

import java.util.LinkedHashMap;
import java.util.Map;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler(ResponseStatusException.class)
    public ResponseEntity<Map<String, Object>> handleResponseStatusException(
            ResponseStatusException exception) {
        HttpStatusCode status = exception.getStatusCode();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", status.value());
        body.put("message", exception.getReason() == null
                ? "The request could not be completed." : exception.getReason());
        return ResponseEntity.status(status).body(body);
    }
}
