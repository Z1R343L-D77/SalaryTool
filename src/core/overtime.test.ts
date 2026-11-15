import { describe, expect, it } from "vitest";
import {
  DEFAULT_DAILY_HOURS,
  DEFAULT_MONTHLY_DAYS,
  calcOvertime,
  createDefaultOvertime,
  equivalentWeekdayHours,
  hourlyBaseOf,
} from "./overtime";
import type { OvertimeInput } from "./overtime";

/** 月薪模式的输入 */
const monthly = (base: number, overrides: Partial<OvertimeInput> = {}): OvertimeInput => ({
  ...createDefaultOvertime(base),
  ...overrides,
});

/** 时薪模式的输入 */
const hourly = (rate: number, overrides: Partial<OvertimeInput> = {}): OvertimeInput => ({
  ...createDefaultOvertime(0),
  mode: "hourly",
  hourlyRate: rate,
  ...overrides,
});

describe("小时工资折算（月薪模式）", () => {
  it("按 21.75 天 / 8 小时折算", () => {
    // 8700 / 21.75 / 8 = 50
    expect(hourlyBaseOf(monthly(8700))).toBe(50);
  });

  it("月薪 17400 时小时工资正好 100", () => {
    // 17400 / 174 = 100
    expect(hourlyBaseOf(monthly(17400))).toBe(100);
  });

  it("月计薪天数为 0 时返回 0，不崩", () => {
    expect(hourlyBaseOf(monthly(10000, { monthlyDays: 0 }))).toBe(0);
  });

  it("日工时为 0 时返回 0", () => {
    expect(hourlyBaseOf(monthly(10000, { dailyHours: 0 }))).toBe(0);
  });

  it("负数基数按 0 处理", () => {
    expect(hourlyBaseOf(monthly(-1000))).toBe(0);
  });
});

describe("小时工资（时薪模式）", () => {
  it("直接用填写的小时工资，不做折算", () => {
    expect(hourlyBaseOf(hourly(50))).toBe(50);
  });

  it("时薪不受月计薪天数影响", () => {
    expect(hourlyBaseOf(hourly(80, { monthlyDays: 0, dailyHours: 0 }))).toBe(80);
  });

  it("时薪模式的加班费按倍率直接相乘", () => {
    const r = calcOvertime(hourly(100, { weekdayHours: 2, weekendHours: 3, holidayHours: 1 }));
    expect(r.weekdayRate).toBe(150);
    expect(r.weekendRate).toBe(200);
    expect(r.holidayRate).toBe(300);
    expect(r.weekdayPay).toBe(300);
    expect(r.weekendPay).toBe(600);
    expect(r.holidayPay).toBe(300);
    expect(r.totalPay).toBe(1200);
  });

  it("负数时薪按 0 处理", () => {
    expect(hourlyBaseOf(hourly(-100))).toBe(0);
  });
});

describe("三档倍率（月薪模式）", () => {
  it("1.5 / 2 / 3 倍单价正确", () => {
    const r = calcOvertime(monthly(17400, { weekdayHours: 1, weekendHours: 1, holidayHours: 1 }));
    expect(r.hourlyBase).toBe(100);
    expect(r.weekdayRate).toBe(150);
    expect(r.weekendRate).toBe(200);
    expect(r.holidayRate).toBe(300);
  });

  it("分别累计三档金额", () => {
    const r = calcOvertime(
      monthly(17400, { weekdayHours: 10, weekendHours: 8, holidayHours: 3 }),
    );
    expect(r.weekdayPay).toBe(1500);
    expect(r.weekendPay).toBe(1600);
    expect(r.holidayPay).toBe(900);
    expect(r.totalHours).toBe(21);
    expect(r.totalPay).toBe(4000);
  });

  it("没有工时时全部为 0", () => {
    const r = calcOvertime(monthly(17400));
    expect(r.totalPay).toBe(0);
    expect(r.totalHours).toBe(0);
    // 单价仍然算出来，方便用户看到折算标准
    expect(r.hourlyBase).toBe(100);
  });

  it("负数工时按 0 处理", () => {
    const r = calcOvertime(monthly(17400, { weekdayHours: -5 }));
    expect(r.weekdayPay).toBe(0);
  });
});

describe("反推（对账）", () => {
  it("1200 元按 1.5 倍折算 16 小时（基数 8700）", () => {
    const hours = equivalentWeekdayHours(1200, monthly(8700));
    // 时薪 50 × 1.5 = 75 → 1200 / 75 = 16
    expect(hours).toBe(16);
  });

  it("时薪模式下同样能反推", () => {
    const hours = equivalentWeekdayHours(300, hourly(100));
    // 300 / (100 × 1.5) = 2
    expect(hours).toBe(2);
  });

  it("基数非法时返回 0", () => {
    expect(equivalentWeekdayHours(1000, monthly(0))).toBe(0);
  });
});

describe("模式默认值", () => {
  it("默认是月薪模式", () => {
    const input = createDefaultOvertime(8000);
    expect(input.mode).toBe("monthly");
    expect(input.base).toBe(8000);
    expect(input.hourlyRate).toBe(0);
    expect(input.monthlyDays).toBe(DEFAULT_MONTHLY_DAYS);
    expect(input.dailyHours).toBe(DEFAULT_DAILY_HOURS);
  });
});
