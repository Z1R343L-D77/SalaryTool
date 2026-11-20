import { describe, expect, it } from "vitest";
import {
  calcMealAllowance,
  calcMealFromCalendar,
  calcMealManual,
  createDefaultMealAllowance,
  createDefaultMealRates,
  emptyMealCounts,
  mealAmount,
  mealCountTotal,
  resolveMealScene,
  suggestMealsFromOvertime,
} from "./mealAllowance";

describe("误餐补贴：单价与金额", () => {
  it("餐次 × 单价求和", () => {
    expect(mealAmount({ breakfast: 0, lunch: 0, dinner: 2 }, { breakfast: 0, lunch: 0, dinner: 20 })).toBe(40);
    expect(mealAmount({ breakfast: 1, lunch: 1, dinner: 1 }, { breakfast: 20, lunch: 40, dinner: 40 })).toBe(100);
    expect(mealAmount(emptyMealCounts(), { breakfast: 20, lunch: 40, dinner: 40 })).toBe(0);
  });

  it("负数和 NaN 都归零", () => {
    expect(mealAmount({ breakfast: -1, lunch: 1, dinner: 0 }, { breakfast: 20, lunch: 40, dinner: 40 })).toBe(40);
    expect(mealAmount({ breakfast: Number.NaN, lunch: 1, dinner: 0 }, { breakfast: 20, lunch: 40, dinner: 40 })).toBe(40);
  });

  it("餐次合计", () => {
    expect(mealCountTotal({ breakfast: 1, lunch: 2, dinner: 3 })).toBe(6);
    expect(mealCountTotal(emptyMealCounts())).toBe(0);
  });
});

describe("误餐补贴：默认单价", () => {
  const rates = createDefaultMealRates();

  it("工作日只有晚饭 20", () => {
    expect(rates.workday).toEqual({ breakfast: 0, lunch: 0, dinner: 20 });
  });

  it("周末午饭 40 + 晚饭 20", () => {
    expect(rates.weekend).toEqual({ breakfast: 0, lunch: 40, dinner: 20 });
  });

  it("出差三餐 20 / 40 / 40", () => {
    expect(rates.trip).toEqual({ breakfast: 20, lunch: 40, dinner: 40 });
  });
});

describe("误餐补贴：档位判断", () => {
  it("出差优先于日期类型", () => {
    expect(resolveMealScene("workday", true)).toBe("trip");
    expect(resolveMealScene("rest", true)).toBe("trip");
    expect(resolveMealScene("holiday", true)).toBe("trip");
  });

  it("不按日期类型：工作日归 workday，其余都归 weekend", () => {
    expect(resolveMealScene("workday", false)).toBe("workday");
    expect(resolveMealScene("rest", false)).toBe("weekend");
    // 法定节假日与周末同档
    expect(resolveMealScene("holiday", false)).toBe("weekend");
  });
});

describe("误餐补贴：手填模式", () => {
  it("三档分别按各自单价算", () => {
    const input = createDefaultMealAllowance();
    input.manual.workday = { breakfast: 0, lunch: 0, dinner: 10 };   // 10 × 20 = 200
    input.manual.weekend = { breakfast: 0, lunch: 3, dinner: 3 };     // 3 × 40 + 3 × 20 = 180
    input.manual.trip = { breakfast: 2, lunch: 4, dinner: 4 };        // 2×20 + 4×40 + 4×40 = 360

    const result = calcMealManual(input);
    expect(result.workday).toBe(200);
    expect(result.weekend).toBe(180);
    expect(result.trip).toBe(360);
    expect(result.total).toBe(740);
    expect(result.totalMeals).toBe(10 + 6 + 10);
  });

  it("改单价立刻反映到金额", () => {
    const input = createDefaultMealAllowance();
    input.manual.workday = { breakfast: 0, lunch: 0, dinner: 10 };
    expect(calcMealManual(input).workday).toBe(200);

    input.rates.workday.dinner = 30;
    expect(calcMealManual(input).workday).toBe(300);
  });

  it("全零时结果为 0", () => {
    const result = calcMealManual(createDefaultMealAllowance());
    expect(result.total).toBe(0);
    expect(result.totalMeals).toBe(0);
  });
});

describe("误餐补贴：日历模式", () => {
  it("按日期类型分档累加", () => {
    const input = createDefaultMealAllowance();
    input.entryMode = "calendar";
    input.calendar = {
      year: 2026,
      month: 11,
      // 2026-11-02 周一（工作日）、11-07 周六（休息日）
      meals: {
        "2026-11-02": { breakfast: 0, lunch: 0, dinner: 1 },     // 工作日：20
        "2026-11-03": { breakfast: 0, lunch: 0, dinner: 1 },     // 工作日：20
        "2026-11-07": { breakfast: 0, lunch: 1, dinner: 1 },     // 休息日：40 + 20 = 60
      },
      trips: {},
      overrides: {},
    };

    const result = calcMealFromCalendar(input.calendar, input.rates);
    expect(result.workday).toBe(40);
    expect(result.weekend).toBe(60);
    expect(result.trip).toBe(0);
    expect(result.total).toBe(100);
    expect(result.totalMeals).toBe(4);
  });

  it("出差标记会整套换成出差单价", () => {
    const input = createDefaultMealAllowance();
    input.calendar = {
      year: 2026,
      month: 11,
      // 这一天本来是工作日，标了出差
      meals: { "2026-11-02": { breakfast: 1, lunch: 1, dinner: 1 } },
      trips: { "2026-11-02": true },
      overrides: {},
    };

    const result = calcMealFromCalendar(input.calendar, input.rates);
    expect(result.trip).toBe(100);   // 20 + 40 + 40
    expect(result.workday).toBe(0);
  });

  it("手动把周末改成工作日，餐次按工作日单价算", () => {
    const input = createDefaultMealAllowance();
    input.calendar = {
      year: 2026,
      month: 11,
      meals: { "2026-11-07": { breakfast: 0, lunch: 1, dinner: 1 } },
      trips: {},
      // 11-07 默认是周六，手动改成工作日（例如调休上班）
      overrides: { "2026-11-07": "workday" },
    };

    const result = calcMealFromCalendar(input.calendar, input.rates);
    // 工作日档：午饭 0 + 晚饭 20 = 20
    expect(result.workday).toBe(20);
    expect(result.weekend).toBe(0);
  });

  it("空日历结果为 0", () => {
    const input = createDefaultMealAllowance();
    const result = calcMealFromCalendar(input.calendar, input.rates);
    expect(result.total).toBe(0);
  });
});

describe("误餐补贴：入口分发", () => {
  it("manual 走手填，calendar 走日历", () => {
    const input = createDefaultMealAllowance();
    input.manual.workday = { breakfast: 0, lunch: 0, dinner: 5 };
    expect(calcMealAllowance(input).total).toBe(100);

    input.entryMode = "calendar";
    input.calendar.meals = { "2026-11-02": { breakfast: 0, lunch: 0, dinner: 2 } };
    expect(calcMealAllowance(input).total).toBe(40);
  });
});

describe("误餐补贴：从加班记录补餐次", () => {
  it("工作日有加班 → 勾晚饭；周末有加班 → 勾午饭和晚饭", () => {
    const overtime = {
      year: 2026,
      month: 11,
      hours: { "2026-11-02": 2, "2026-11-07": 8 },   // 周一是工作日，周六是休息日
      overrides: {},
    };
    const target = createDefaultMealAllowance();
    const meals = suggestMealsFromOvertime(overtime, target.calendar);

    expect(meals["2026-11-02"]).toEqual({ breakfast: 0, lunch: 0, dinner: 1 });
    expect(meals["2026-11-07"]).toEqual({ breakfast: 0, lunch: 1, dinner: 1 });
  });

  it("没有加班的日子不填", () => {
    const overtime = { year: 2026, month: 11, hours: {}, overrides: {} };
    const meals = suggestMealsFromOvertime(overtime, createDefaultMealAllowance().calendar);
    expect(Object.keys(meals).length).toBe(0);
  });

  it("已填过的日子不覆盖", () => {
    const overtime = { year: 2026, month: 11, hours: { "2026-11-02": 3 }, overrides: {} };
    const target = createDefaultMealAllowance();
    target.calendar.meals = { "2026-11-02": { breakfast: 1, lunch: 1, dinner: 1 } };
    const meals = suggestMealsFromOvertime(overtime, target.calendar);
    // 保持原值
    expect(meals["2026-11-02"]).toEqual({ breakfast: 1, lunch: 1, dinner: 1 });
  });
});
