import { describe, expect, it } from "vitest";
import {
  MAX_YEAR,
  MIN_YEAR,
  buildMonth,
  dayKeyOf,
  defaultDayType,
  flattenMonth,
  isFixedStatutory,
  summarizeMonth,
  weekdayOf,
} from "./calendar";

describe("日期工具", () => {
  it("日期键补零", () => {
    expect(dayKeyOf(2026, 3, 7)).toBe("2026-03-07");
    expect(dayKeyOf(2026, 11, 14)).toBe("2026-11-14");
  });

  it("周一为 0、周日为 6", () => {
    // 2025-01-06 是周一
    expect(weekdayOf(2025, 1, 6)).toBe(0);
    // 2025-01-05 是周日
    expect(weekdayOf(2025, 1, 5)).toBe(6);
    // 2026-11-14 是周六
    expect(weekdayOf(2026, 11, 14)).toBe(5);
  });

  it("年份范围是 2025–2045", () => {
    expect(MIN_YEAR).toBe(2025);
    expect(MAX_YEAR).toBe(2045);
  });
});

describe("法定节假日", () => {
  it("固定的法定节假日能识别", () => {
    expect(isFixedStatutory(1, 1)).toBe(true); // 元旦
    expect(isFixedStatutory(5, 1)).toBe(true); // 劳动节
    expect(isFixedStatutory(5, 2)).toBe(true);
    expect(isFixedStatutory(10, 1)).toBe(true);
    expect(isFixedStatutory(10, 3)).toBe(true);
  });

  it("非节假日返回 false", () => {
    expect(isFixedStatutory(5, 3)).toBe(false);
    expect(isFixedStatutory(10, 4)).toBe(false);
    expect(isFixedStatutory(3, 15)).toBe(false);
  });

  it("默认档位：该怎么判", () => {
    // 2026-11-14 周六 → 休息日
    expect(defaultDayType(2026, 11, 14)).toBe("rest");
    // 2026-11-16 周一 → 工作日
    expect(defaultDayType(2026, 11, 16)).toBe("workday");
    // 10 月 1 日 → 法定节假日
    expect(defaultDayType(2030, 10, 1)).toBe("holiday");
  });

  it("2025 年春节按公布安排标为节假日", () => {
    expect(defaultDayType(2025, 1, 29)).toBe("holiday");
    expect(defaultDayType(2025, 1, 28)).toBe("holiday");
    // 未收录的年份不会误标
    expect(defaultDayType(2030, 1, 29)).not.toBe("holiday");
  });
});

describe("生成月历", () => {
  it("2026 年 11 月：30 天，1 号是周日，前面补 6 格空位", () => {
    const weeks = buildMonth({ year: 2026, month: 11, overrides: {}, hours: {} });
    const days = flattenMonth(weeks);
    expect(days.length).toBe(30);
    expect(days[0].day).toBe(1);
    expect(days[0].weekday).toBe(6); // 周日
    // 6 个前导空格 + 30 天 = 36 格，排 6 周（最后一周只填 1 格）
    expect(weeks.length).toBe(6);
    expect(weeks[0].filter(Boolean).length).toBe(1);
  });

  it("2025 年 2 月：28 天", () => {
    const days = flattenMonth(buildMonth({ year: 2025, month: 2, overrides: {}, hours: {} }));
    expect(days.length).toBe(28);
  });

  it("闰年 2028 年 2 月：29 天", () => {
    const days = flattenMonth(buildMonth({ year: 2028, month: 2, overrides: {}, hours: {} }));
    expect(days.length).toBe(29);
  });

  it("每年 2 月都能正常生成（2025-2045 全量跑一遍）", () => {
    for (let year = MIN_YEAR; year <= MAX_YEAR; year += 1) {
      const weeks = buildMonth({ year, month: 2, overrides: {}, hours: {} });
      const days = flattenMonth(weeks);
      const expected = new Date(year, 2, 0).getDate();
      expect(days.length, `${year} 年 2 月`).toBe(expected);
      // 每周必须是 7 列
      for (const week of weeks) expect(week.length).toBe(7);
    }
  });

  it("手动覆盖类型优先于默认判断", () => {
    const days = flattenMonth(
      buildMonth({
        year: 2026,
        month: 11,
        overrides: { "2026-11-16": "holiday" }, // 周一改成节假日
        hours: {},
      }),
    );
    const target = days.find((d) => d.day === 16)!;
    expect(target.type).toBe("holiday");
    expect(target.overridden).toBe(true);
  });

  it("工时与今天标记能带入", () => {
    const days = flattenMonth(
      buildMonth({
        year: 2026,
        month: 11,
        overrides: {},
        hours: { "2026-11-14": 4 },
        today: "2026-11-14",
      }),
    );
    const target = days.find((d) => d.day === 14)!;
    expect(target.hours).toBe(4);
    expect(target.isToday).toBe(true);
  });

  it("年份越界会被夹到范围内", () => {
    const days = flattenMonth(buildMonth({ year: 1999, month: 6, overrides: {}, hours: {} }));
    expect(days[0].year).toBe(MIN_YEAR);
  });
});

describe("月度工时汇总", () => {
  it("按档位分组累加", () => {
    const days = flattenMonth(
      buildMonth({
        year: 2026,
        month: 11,
        overrides: { "2026-11-16": "holiday" }, // 周一 → 节假日
        hours: {
          "2026-11-16": 8, // 节假日
          "2026-11-14": 4, // 周六 → 休息日
          "2026-11-17": 2, // 周二 → 工作日
          "2026-11-18": 3, // 周三 → 工作日
        },
      }),
    );
    const summary = summarizeMonth(days);
    expect(summary.holidayHours).toBe(8);
    expect(summary.restHours).toBe(4);
    expect(summary.workdayHours).toBe(5);
    expect(summary.totalHours).toBe(17);
    expect(summary.workedDays).toBe(4);
  });

  it("没有工时全为 0", () => {
    const days = flattenMonth(buildMonth({ year: 2026, month: 11, overrides: {}, hours: {} }));
    const summary = summarizeMonth(days);
    expect(summary).toMatchObject({
      workdayHours: 0,
      restHours: 0,
      holidayHours: 0,
      totalHours: 0,
      workedDays: 0,
    });
  });
});
