package main

import (
	"context"
	"testing"
)

func TestHandler(t *testing.T) {
	req := Request{Name: "world"}
	resp, err := handler(context.Background(), req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	expected := "Hello, world!"
	if resp.Message != expected {
		t.Errorf("got %q, want %q", resp.Message, expected)
	}
}
