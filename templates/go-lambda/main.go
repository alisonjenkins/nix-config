package main

import (
	"context"
	"fmt"

	"github.com/aws/aws-lambda-go/lambda"
)

type Request struct {
	Name string `json:"name"`
}

type Response struct {
	Message string `json:"message"`
}

func handler(ctx context.Context, req Request) (Response, error) {
	return Response{
		Message: fmt.Sprintf("Hello, %s!", req.Name),
	}, nil
}

func main() {
	lambda.Start(handler)
}
