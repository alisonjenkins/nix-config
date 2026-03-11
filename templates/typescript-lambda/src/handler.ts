import type { Handler } from "aws-lambda";

interface Request {
  name?: string;
}

interface Response {
  message: string;
}

export const handler: Handler<Request, Response> = async (event) => {
  const name = event.name ?? "world";
  return {
    message: `Hello, ${name}!`,
  };
};
