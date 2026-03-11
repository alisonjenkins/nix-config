package com.example;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

import org.junit.jupiter.api.Test;

class MainTest {
  @Test
  void mainRunsWithoutException() {
    assertDoesNotThrow(() -> Main.main(new String[] {}));
  }
}
