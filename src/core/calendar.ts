import { round2, toNonNegative } from "./money";

/**
 * 加班日历：按天填写工时，自动判断当天属于哪一档倍率。
 *
 * 三档定义（《劳动法》第 44 条）：
 * - 工作日（周一至周五）：1.5 倍
 * - 休息日（周六周日、调休放假日）：2 倍
 * - 法定节假日：3 倍
 *
 * 关于节假日数据的说明：
 * 只有《全国年节及纪念日放假办法》里日期固定的节日可以自动判断——
 * 元旦 1/1、劳动节 5/1–5/2、国庆 10/1–10/3。春节、清明、端午、中秋按农历算，
 * 每年日期不同，且调休安排由国务院逐年公布，因此不内置，需要在日历上手动标记。
 */

export type DayType = "workday" | "rest" | "holiday";

/** 年份范围。 */
export const MIN_YEAR = 2025;
export const MAX_YEAR = 2045;

export const WEEKDAY_LABELS = ["一", "二", "三", "四", "五", "六", "日"] as const;

export const DAY_TYPE_META: Record<
  DayType,
  { label: string; short: string; multiplier: number }
> = {
  workday: { label: "工作日", short: "班", multiplier: 1.5 },
  rest: { label: "休息日", short: "休", multiplier: 2 },
  holiday: { label: "法定节假日", short: "假", multiplier: 3 },
};

/** 日期键，形如 2026-11-14。 */
export function dayKeyOf(year: number, month: number, day: number): string {
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

/**
 * 日期固定的法定节假日（所有年份通用，来自《全国年节及纪念日放假办法》）。
 *
 * 2025 年起劳动节由 1 天增加到 2 天，这里按现行规定实现。
 */
export function isFixedStatutory(month: number, day: number): boolean {
  if (month === 1 && day === 1) return true;
  if (month === 5 && (day === 1 || day === 2)) return true;
  if (month === 10 && (day >= 1 && day <= 3)) return true;
  return false;
}

/**
 * 农历节日的法定日期（按月日列出），目前只收录已正式公布的年份。
 *
 * 未收录的年份不会自动标记，需要在日历上点一下手动设为「法定节假日」。
 */
const LUNAR_STATUTORY: Record<number, string[]> = {
  // 2025 年（国务院办公厅 2025 年放假安排）
  2025: [
    "01-28", // 除夕
    "01-29", // 春节
    "01-30",
    "01-31",
    "04-04", // 清明
    "05-31", // 端午
    "10-06", // 中秋
  ],
};

function isLunarStatutory(year: number, month: number, day: number): boolean {
  const list = LUNAR_STATUTORY[year];
  if (!list) return false;
  const key = `${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
  return list.includes(key);
}

/** 周一为 0，周日为 6。 */
export function weekdayOf(year: number, month: number, day: number): number {
  return (new Date(year, month - 1, day).getDay() + 6) % 7;
}

/** 某天默认属于哪一档（未考虑用户手动覆盖）。 */
export function defaultDayType(year: number, month: number, day: number): DayType {
  if (isFixedStatutory(month, day) || isLunarStatutory(year, month, day)) return "holiday";
  const weekday = weekdayOf(year, month, day);
  return weekday >= 5 ? "rest" : "workday";
}

export interface CalendarDay {
  key: string;
  year: number;
  month: number;
  day: number;
  /** 周一为 0 */
  weekday: number;
  type: DayType;
  /** 是否用户手动改过类型 */
  overridden: boolean;
  hours: number;
  isToday: boolean;
}

export interface CalendarMonthInput {
  year: number;
  month: number;
  /** 日期键 → 手动指定的类型 */
  overrides: Record<string, DayType>;
  /** 日期键 → 加班小时数 */
  hours: Record<string, number>;
  /** 今天的日期键，用于高亮；不传则不标记 */
  today?: string;
}

/** 生成一个月的日历（周一到周日排列），首尾补 null 对齐星期。 */
export function buildMonth(input: CalendarMonthInput): Array<Array<CalendarDay | null>> {
  const year = Math.min(MAX_YEAR, Math.max(MIN_YEAR, Math.round(input.year)));
  const month = Math.min(12, Math.max(1, Math.round(input.month)));
  const daysInMonth = new Date(year, month, 0).getDate();
  const firstWeekday = weekdayOf(year, month, 1);

  const cells: Array<CalendarDay | null> = Array.from({ length: firstWeekday }, () => null);

  for (let day = 1; day <= daysInMonth; day += 1) {
    const key = dayKeyOf(year, month, day);
    const override = input.overrides[key];
    cells.push({
      key,
      year,
      month,
      day,
      weekday: weekdayOf(year, month, day),
      type: override ?? defaultDayType(year, month, day),
      overridden: override !== undefined,
      hours: round2(toNonNegative(input.hours[key])),
      isToday: input.today === key,
    });
  }

  // 补到整周
  while (cells.length % 7 !== 0) cells.push(null);

  const weeks: Array<Array<CalendarDay | null>> = [];
  for (let i = 0; i < cells.length; i += 7) {
    weeks.push(cells.slice(i, i + 7));
  }
  return weeks;
}

export interface CalendarSummary {
  workdayHours: number;
  restHours: number;
  holidayHours: number;
  totalHours: number;
  /** 有加班记录的天数 */
  workedDays: number;
}

/** 汇总一个月的工时，按档位分组，供加班费计算使用。 */
export function summarizeMonth(days: ReadonlyArray<CalendarDay | null>): CalendarSummary {
  let workdayHours = 0;
  let restHours = 0;
  let holidayHours = 0;
  let workedDays = 0;

  for (const day of days) {
    if (!day || day.hours <= 0) continue;
    workedDays += 1;
    if (day.type === "holiday") holidayHours += day.hours;
    else if (day.type === "rest") restHours += day.hours;
    else workdayHours += day.hours;
  }

  return {
    workdayHours: round2(workdayHours),
    restHours: round2(restHours),
    holidayHours: round2(holidayHours),
    totalHours: round2(workdayHours + restHours + holidayHours),
    workedDays,
  };
}

/** 把整月的格子摊平成数组。 */
export function flattenMonth(weeks: ReadonlyArray<ReadonlyArray<CalendarDay | null>>): CalendarDay[] {
  return weeks.flatMap((week) => week.filter((day): day is CalendarDay => day !== null));
}

/** 星期序号转中文，用于日历上的「周一」。 */
export function weekdayLabel(weekday: number): string {
  return WEEKDAY_LABELS[Math.min(6, Math.max(0, weekday))];
}
