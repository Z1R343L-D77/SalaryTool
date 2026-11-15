import { describe, expect, it } from "vitest";
import {
  DEFAULT_DAILY_HOURS,
  DEFAULT_MONTHLY_DAYS,
  calcOvertime,
  createDefaultOvertime,
  equivalentWeekdayHours,
  hourlyBaseOf,
  hourlyToMonthly,
  monthlyToHourly,
  summarizeCalendarHours,
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

describe("月薪 ↔ 时薪互转", () => {
  it("月薪折算成时薪", () => {
    // 8700 / 21.75 / 8 = 50
    expect(monthlyToHourly(8700, 21.75, 8)).toBe(50);
  });

  it("时薪折回月薪", () => {
    // 50 × 21.75 × 8 = 8700
    expect(hourlyToMonthly(50, 21.75, 8)).toBe(8700);
  });

  it("两者互为逆运算", () => {
    for (const base of [5000, 6700, 8700, 15000, 23333.33]) {
      const rate = monthlyToHourly(base, DEFAULT_MONTHLY_DAYS, DEFAULT_DAILY_HOURS);
      // 传入原月薪：时薪折出来和它一致时保留原值，不让两位小数的误差往上漂
      expect(hourlyToMonthly(rate, DEFAULT_MONTHLY_DAYS, DEFAULT_DAILY_HOURS, base)).toBe(base);
    }
  });

  it("不传原月薪时按纯折算（会有分位误差）", () => {
    // 5000 / 174 = 28.74 → 28.74 × 174 = 5000.76
    expect(hourlyToMonthly(28.74, 21.75, 8)).toBe(5000.76);
  });

  it("时薪真的改了才用折算值，不会被原月薪卡住", () => {
    // 原月薪 15000（时薪 86.21），改成时薪 90 → 应该得到 90 × 174 = 15660
    expect(hourlyToMonthly(90, 21.75, 8, 15000)).toBe(15660);
  });

  it("手填的时薪 22.32 折算回月薪", () => {
    // 22.32 × 21.75 × 8 = 3883.68
    expect(hourlyToMonthly(22.32, 21.75, 8)).toBe(3883.68);
  });

  it("计薪天数或日工时为 0 时都返回 0", () => {
    expect(monthlyToHourly(8700, 0, 8)).toBe(0);
    expect(monthlyToHourly(8700, 21.75, 0)).toBe(0);
    expect(hourlyToMonthly(50, 0, 8)).toBe(0);
    expect(hourlyToMonthly(50, 21.75, 0)).toBe(0);
  });

  it("负数按 0 处理", () => {
    expect(monthlyToHourly(-8700, 21.75, 8)).toBe(0);
    expect(hourlyToMonthly(-50, 21.75, 8)).toBe(0);
  });
});

describe("日历汇总", () => {
  const withCalendar = (
    hours: Record<string, number>,
    overrides: Record<string, "workday" | "rest" | "holiday"> = {},
  ): OvertimeInput => ({
    ...createDefaultOvertime(8700),
    entryMode: "calendar",
    calendar: { year: 2026, month: 11, hours, overrides },
  });

  it("按日期自动分档汇总", () => {
    // 2026-11-16 周一（工作日）、11-14 周六（休息日）、11-17 周二（工作日）
    const r = summarizeCalendarHours(withCalendar({
      "2026-11-16": 2,
      "2026-11-14": 4,
      "2026-11-17": 3,
    }).calendar);
    expect(r.weekdayHours).toBe(5);
    expect(r.weekendHours).toBe(4);
    expect(r.holidayHours).toBe(0);
  });

  it("手动改档位会改变汇总到哪一档", () => {
    const r = summarizeCalendarHours(
      withCalendar({ "2026-11-16": 8 }, { "2026-11-16": "holiday" }).calendar,
    );
    expect(r.weekdayHours).toBe(0);
    expect(r.holidayHours).toBe(8);
  });

  it("日历模式下 calcOvertime 用日历汇总，不用手填的合计", () => {
    const input = {
      ...withCalendar({ "2026-11-16": 2 }),
      weekdayHours: 100, // 手填的合计不该参与计算
    };
    const r = calcOvertime(input);
    expect(r.totalHours).toBe(2);
    // 时薪 50 × 1.5 × 2 小时 = 150
    expect(r.totalPay).toBe(150);
  });

  it("日历为空时汇总为 0", () => {
    const r = summarizeCalendarHours(withCalendar({}).calendar);
    expect(r.weekdayHours + r.weekendHours + r.holidayHours).toBe(0);
  });

  it("手工模式下忽略日历数据", () => {
    const input = {
      ...withCalendar({ "2026-11-16": 8 }),
      entryMode: "manual" as const,
      weekdayHours: 3,
    };
    expect(calcOvertime(input).totalHours).toBe(3);
  });
});
