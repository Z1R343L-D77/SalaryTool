import { describe, expect, it } from "vitest";
import { formatMoney, formatRate, round2, safeDivide, sumBy, toAmount, toNonNegative } from "./money";

describe("round2", () => {
  it("保留两位小数", () => {
    expect(round2(1.005)).toBe(1.01);
    expect(round2(1.004)).toBe(1);
    expect(round2(1234.5678)).toBe(1234.57);
  });

  it("非法值返回 0", () => {
    expect(round2(Number.NaN)).toBe(0);
    expect(round2(Number.POSITIVE_INFINITY)).toBe(0);
  });
});

describe("toAmount", () => {
  it("解析带千分位和货币符号的字符串", () => {
    expect(toAmount("1,234.56")).toBe(1234.56);
    expect(toAmount("¥ 2000")).toBe(2000);
    expect(toAmount("-300")).toBe(-300);
    expect(toAmount("12元")).toBe(12);
  });

  it("空值与非法值走 fallback", () => {
    expect(toAmount("")).toBe(0);
    expect(toAmount("abc", 9)).toBe(9);
    expect(toAmount(undefined, 5)).toBe(5);
  });
});

describe("toNonNegative", () => {
  it("负数归零", () => {
    expect(toNonNegative(-100)).toBe(0);
    expect(toNonNegative("-1")).toBe(0);
    expect(toNonNegative("250")).toBe(250);
  });
});

describe("formatMoney", () => {
  it("千分位 + 两位小数", () => {
    expect(formatMoney(12345.6)).toBe("12,345.60");
    expect(formatMoney(0)).toBe("0.00");
  });
});

describe("formatRate", () => {
  it("小数转百分比", () => {
    expect(formatRate(0.0325)).toBe("3.25%");
    expect(formatRate(0.1)).toBe("10%");
    expect(formatRate(0)).toBe("0%");
    expect(formatRate(0.125, 1)).toBe("12.5%");
  });
});

describe("sumBy", () => {
  it("求和并保留两位小数", () => {
    expect(sumBy([{ v: 1.111 }, { v: 2.222 }], (x) => x.v)).toBe(3.33);
  });
});

describe("safeDivide", () => {
  it("分母为 0 返回 0", () => {
    expect(safeDivide(1, 0)).toBe(0);
    expect(safeDivide(9, 3)).toBe(3);
  });
});
