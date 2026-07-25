import { describe, expect, test } from "bun:test";
import { formatLocalTime, safeLink } from "../src/ui/NotificationCard";

describe("notification UI utilities", () => {
  test("allows only web links", () => {
    expect(safeLink("https://example.com/build?id=4")).toBe("https://example.com/build?id=4");
    expect(safeLink("http://localhost:3000/result")).toBe("http://localhost:3000/result");
    expect(safeLink("javascript:alert(1)")).toBeNull();
    expect(safeLink("not a URL")).toBeNull();
    expect(safeLink(null)).toBeNull();
  });

  test("formats timestamps and preserves invalid values", () => {
    expect(formatLocalTime("2026-01-02T03:04:05.000Z")).not.toBe("2026-01-02T03:04:05.000Z");
    expect(formatLocalTime("not-a-date")).toBe("not-a-date");
  });
});
