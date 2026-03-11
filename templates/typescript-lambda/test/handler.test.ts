import { describe, it } from "node:test";
import * as assert from "node:assert";
import { handler } from "../src/handler";

describe("handler", () => {
  it("should greet with provided name", async () => {
    const result = await handler({ name: "world" }, {} as any, () => {});
    assert.deepStrictEqual(result, { message: "Hello, world!" });
  });

  it("should default to world", async () => {
    const result = await handler({}, {} as any, () => {});
    assert.deepStrictEqual(result, { message: "Hello, world!" });
  });
});
