package com.example;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.Map;
import org.junit.jupiter.api.Test;

class HandlerTest {
  @Test
  void handlerReturnsGreeting() {
    Handler handler = new Handler();
    Map<String, Object> event = Map.of("name", "world");
    Map<String, Object> result = handler.handleRequest(event, null);
    assertEquals("Hello, world!", result.get("message"));
  }
}
