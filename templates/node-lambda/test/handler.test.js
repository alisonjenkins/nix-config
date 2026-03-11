const { describe, it } = require("node:test");
const assert = require("node:assert");
const { handler } = require("../src/handler");

describe("handler", () => {
  it("should greet with provided name", async () => {
    const result = await handler({ name: "world" });
    assert.deepStrictEqual(result, { message: "Hello, world!" });
  });

  it("should default to world", async () => {
    const result = await handler({});
    assert.deepStrictEqual(result, { message: "Hello, world!" });
  });
});
