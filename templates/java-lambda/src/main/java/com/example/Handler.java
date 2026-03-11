package com.example;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import java.util.Map;

public class Handler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
  @Override
  public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {
    String name = event.getOrDefault("name", "world").toString();
    return Map.of("message", "Hello, " + name + "!");
  }
}
