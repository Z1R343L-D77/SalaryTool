import { round2, toNonNegative } from "./money";
import type { DayType } from "./calendar";
import { buildMonth, flattenMonth } from "./calendar";

/**
 * 加班误餐补贴。
 *
 * 和加班费是两回事：加班费按「工时 × 倍率」算，误餐补贴按「天数 × 餐次 × 单价」算。
 * 它不涉及法律条文，纯粹看公司制度，所以每一项单价都能改。
 *
 * 档位只有三种：
 * - workday 工作日加班（含法定节假日前后的调休上班日）
 * - weekend 周末 / 法定节假日加班
 * - trip    出差（与日期无关，任何一天都可以标成出差）
 */

/** 一顿饭的类别。 */
export type MealSlot = "breakfast" | "lunch" | "dinner";

export const MEAL_SLOTS: readonly MealSlot[] = ["breakfast", "lunch", "dinner"];

export const MEAL_LABELS: Record<MealSlot, string> = {
  breakfast: "早",
  lunch: "中",
  dinner: "晚",
};

/** 一天能领几餐（0 或 1，留数字类型便于以后支持多份）。 */
export interface MealCounts {
  breakfast: number;
  lunch: number;
  dinner: number;
}

/** 三档的单价。 */
export interface MealRates {
  /** 工作日加班：默认只有晚饭 20 */
  workday: MealCounts;
  /** 周末 / 法定节假日加班：午饭 40 + 晚饭 20 */
  weekend: MealCounts;
  /** 出差：早 20 + 中 40 + 晚 40 */
  trip: MealCounts;
}

/** 发生误餐的场景（决定用哪套单价）。 */
export type MealScene = "workday" | "weekend" | "trip";

export const MEAL_SCENES: readonly MealScene[] = ["workday", "weekend", "trip"];

export const MEAL_SCENE_LABELS: Record<MealScene, string> = {
  workday: "工作日加班",
  weekend: "周末 / 节假日",
  trip: "出差",
};

/** 工时录入方式，和加班费保持一致。 */
export type MealEntryMode = "manual" | "calendar";

export interface MealAllowanceInput {
  entryMode: MealEntryMode;
  rates: MealRates;
  /** 手填模式：三档各自的餐次计数 */
  manual: Record<MealScene, MealCounts>;
  /** 日历模式的数据，按自然月保存 */
  calendar: MealCalendar;
}

/** 日历模式的数据。 */
export interface MealCalendar {
  year: number;
  month: number;
  /** 日期键 → 当天领的餐次 */
  meals: Record<string, MealCounts>;
  /** 日期键 → 是否出差（出差优先于日期类型） */
  trips: Record<string, boolean>;
  /** 日期键 → 手动覆盖的日期类型（复用加班日历的档位概念） */
  overrides: Record<string, DayType>;
}

/** 误餐补贴与收入项的联动设置。 */
export interface MealSyncSettings {
  enabled: boolean;
  incomeId: string | null;
}

export interface MealAllowanceResult {
  /** 三档各自的金额 */
  workday: number;
  weekend: number;
  trip: number;
  /** 三档各自的餐次总数 */
  workdayMeals: number;
  weekendMeals: number;
  tripMeals: number;
  /** 总金额与总餐次 */
  total: number;
  totalMeals: number;
}

/** 一顿也没吃。 */
export function emptyMealCounts(): MealCounts {
  return { breakfast: 0, lunch: 0, dinner: 0 };
}

export function mealCountTotal(counts: MealCounts): number {
  return (
    toNonNegative(counts.breakfast) +
    toNonNegative(counts.lunch) +
    toNonNegative(counts.dinner)
  );
}

/** 餐次 × 单价。 */
export function mealAmount(counts: MealCounts, rates: MealCounts): number {
  return round2(
    toNonNegative(counts.breakfast) * toNonNegative(rates.breakfast) +
      toNonNegative(counts.lunch) * toNonNegative(rates.lunch) +
      toNonNegative(counts.dinner) * toNonNegative(rates.dinner),
  );
}

/** 默认单价：工作日只有晚饭 20；周末午饭 40 晚饭 20；出差三餐 20 / 40 / 40。 */
export function createDefaultMealRates(): MealRates {
  return {
    workday: { breakfast: 0, lunch: 0, dinner: 20 },
    weekend: { breakfast: 0, lunch: 40, dinner: 20 },
    trip: { breakfast: 20, lunch: 40, dinner: 40 },
  };
}

export function createDefaultMealCalendar(year?: number, month?: number): MealCalendar {
  const now = new Date();
  return {
    year: year ?? now.getFullYear(),
    month: month ?? now.getMonth() + 1,
    meals: {},
    trips: {},
    overrides: {},
  };
}

export function createDefaultMealAllowance(): MealAllowanceInput {
  return {
    entryMode: "manual",
    rates: createDefaultMealRates(),
    manual: {
      workday: emptyMealCounts(),
      weekend: emptyMealCounts(),
      trip: emptyMealCounts(),
    },
    calendar: createDefaultMealCalendar(),
  };
}

export function createDefaultMealSync(): MealSyncSettings {
  return { enabled: false, incomeId: null };
}

/**
 * 某天属于哪一档。
 *
 * 出差优先：标了出差就整套换成出差单价，不再看当天是周几。
 * 否则按日期类型走：工作日 → workday，休息日和法定节假日 → weekend。
 */
export function resolveMealScene(dayType: DayType, isTrip: boolean): MealScene {
  if (isTrip) return "trip";
  return dayType === "workday" ? "workday" : "weekend";
}

/** 手填模式的三档结果。 */
export function calcMealManual(input: MealAllowanceInput): MealAllowanceResult {
  const { manual, rates } = input;
  const workday = mealAmount(manual.workday, rates.workday);
  const weekend = mealAmount(manual.weekend, rates.weekend);
  const trip = mealAmount(manual.trip, rates.trip);
  return {
    workday,
    weekend,
    trip,
    workdayMeals: mealCountTotal(manual.workday),
    weekendMeals: mealCountTotal(manual.weekend),
    tripMeals: mealCountTotal(manual.trip),
    total: round2(workday + weekend + trip),
    totalMeals: round2(
      mealCountTotal(manual.workday) +
        mealCountTotal(manual.weekend) +
        mealCountTotal(manual.trip),
    ),
  };
}

/** 日历模式的三档结果：逐天判断档位后累加。 */
export function calcMealFromCalendar(calendar: MealCalendar, rates: MealRates): MealAllowanceResult {
  const weeks = buildMonth({
    year: calendar.year,
    month: calendar.month,
    overrides: calendar.overrides,
    hours: {},
  });

  let workday = 0;
  let weekend = 0;
  let trip = 0;
  let workdayMeals = 0;
  let weekendMeals = 0;
  let tripMeals = 0;

  for (const day of flattenMonth(weeks)) {
    const counts = calendar.meals[day.key];
    if (!counts) continue;
    const total = mealCountTotal(counts);
    if (total <= 0) continue;

    const scene = resolveMealScene(day.type, calendar.trips[day.key] === true);
    if (scene === "trip") {
      trip += mealAmount(counts, rates.trip);
      tripMeals += total;
    } else if (scene === "weekend") {
      weekend += mealAmount(counts, rates.weekend);
      weekendMeals += total;
    } else {
      workday += mealAmount(counts, rates.workday);
      workdayMeals += total;
    }
  }

  return {
    workday: round2(workday),
    weekend: round2(weekend),
    trip: round2(trip),
    workdayMeals,
    weekendMeals,
    tripMeals,
    total: round2(workday + weekend + trip),
    totalMeals: workdayMeals + weekendMeals + tripMeals,
  };
}

/** 按录入方式取结果。 */
export function calcMealAllowance(input: MealAllowanceInput): MealAllowanceResult {
  return input.entryMode === "calendar"
    ? calcMealFromCalendar(input.calendar, input.rates)
    : calcMealManual(input);
}

/**
 * 从加班日历「补餐次」：把加班日历里有工时的那几天，按默认规则勾上餐次。
 *
 * 工作日有加班 → 勾晚饭；周末/节假日有加班 → 勾午饭和晚饭。
 * 已有的餐次不会被覆盖（只填空白），出差标记也不动。
 */
export function suggestMealsFromOvertime(
  overtimeCalendar: { year: number; month: number; hours: Record<string, number>; overrides: Record<string, DayType> },
  target: MealCalendar,
): Record<string, MealCounts> {
  const weeks = buildMonth({
    year: overtimeCalendar.year,
    month: overtimeCalendar.month,
    overrides: overtimeCalendar.overrides,
    hours: overtimeCalendar.hours,
  });

  const result: Record<string, MealCounts> = { ...target.meals };

  for (const day of flattenMonth(weeks)) {
    const hours = overtimeCalendar.hours[day.key] ?? 0;
    if (hours <= 0) continue;
    // 已经填过的日子跳过，避免覆盖手工调整
    const existing = result[day.key];
    if (existing && mealCountTotal(existing) > 0) continue;

    result[day.key] = day.type === "workday"
      ? { breakfast: 0, lunch: 0, dinner: 1 }
      : { breakfast: 0, lunch: 1, dinner: 1 };
  }

  return result;
}
