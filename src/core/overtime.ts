import { round2, round4, toNonNegative } from "./money";
import type { DayType } from "./calendar";
import { buildMonth, flattenMonth, summarizeMonth } from "./calendar";

/**
 * 加班费计算。
 *
 * 依据《劳动法》第 44 条与《关于职工全年月平均工作时间和工资折算问题的通知》：
 * - 日工资 = 月工资基数 ÷ 21.75
 * - 小时工资 = 日工资 ÷ 8 = 月工资基数 ÷ 174
 * - 工作日延长工时：1.5 倍
 * - 休息日（周末）加班且不能安排补休：2 倍
 * - 法定节假日加班：3 倍（不能用补休替代）
 *
 * 21.75 是「月计薪天数」= (365 − 104 个休息日) ÷ 12。
 * 注意它不是月工作日（20.83），算工资相关一律用 21.75。
 */

export const DEFAULT_MONTHLY_DAYS = 21.75;
export const DEFAULT_DAILY_HOURS = 8;

export const WEEKDAY_RATE = 1.5;
export const WEEKEND_RATE = 2;
export const HOLIDAY_RATE = 3;

/**
 * 基数输入方式：
 * - monthly 按月薪折算，小时工资 = 月薪 ÷ 21.75 ÷ 8
 * - hourly  直接填小时工资（有些公司/兼职按小时签约，不需要折算）
 */
export type OvertimeBaseMode = "monthly" | "hourly";

export interface OvertimeInput {
  mode: OvertimeBaseMode;
  /** 工时录入方式：manual 直接填三档合计，calendar 在日历上按天填 */
  entryMode: OvertimeEntryMode;
  /** 月薪模式下的加班费基数（元/月） */
  base: number;
  /** 月薪模式下基数是否自动跟随基本工资 */
  followBasicSalary: boolean;
  /** 时薪模式下的小时工资（元/小时） */
  hourlyRate: number;
  /** 月计薪天数，法定 21.75（仅月薪模式使用） */
  monthlyDays: number;
  /** 每日标准工时，通常 8（仅月薪模式使用） */
  dailyHours: number;
  /** 工作日延长工时（小时） */
  weekdayHours: number;
  /** 休息日加班工时（小时） */
  weekendHours: number;
  /** 法定节假日加班工时（小时） */
  holidayHours: number;
  /** 日历模式的数据 */
  calendar: OvertimeCalendar;
}

/**
 * 工时录入方式：
 * - manual   直接填工作日 / 周末 / 节假日三档合计小时
 * - calendar 在日历上逐天填写，按日期自动判断档位并汇总
 */
export type OvertimeEntryMode = "manual" | "calendar";

/** 日历模式的数据，按自然月保存。 */
export interface OvertimeCalendar {
  year: number;
  month: number;
  /** 日期键（2026-11-14）→ 该天加班小时数 */
  hours: Record<string, number>;
  /** 日期键 → 手动覆盖的档位（用于调休上班、非法定节假日放假等） */
  overrides: Record<string, DayType>;
}

export interface OvertimeResult {
  /** 折算出的小时工资（未加成） */
  hourlyBase: number;
  /** 三档的小时单价 */
  weekdayRate: number;
  weekendRate: number;
  holidayRate: number;
  weekdayPay: number;
  weekendPay: number;
  holidayPay: number;
  totalHours: number;
  totalPay: number;
}

/**
 * 加班费与收入项的联动设置。
 *
 * 打开后，算出的加班费合计会写进指定的收入项；工资计算、社保基数、
 * 个税都会跟着变，不用再手工抄一遍。
 */
export interface OvertimeSyncSettings {
  enabled: boolean;
  /** 同步目标收入项 id；null 表示还没绑定，由 store 自动查找或新建「加班费」 */
  incomeId: string | null;
}

/** 当前月份（日历模式的初始值）。 */
export function currentYearMonth(): { year: number; month: number } {
  const now = new Date();
  return { year: now.getFullYear(), month: now.getMonth() + 1 };
}

export function createDefaultCalendar(year?: number, month?: number): OvertimeCalendar {
  const today = currentYearMonth();
  return {
    year: year ?? today.year,
    month: month ?? today.month,
    hours: {},
    overrides: {},
  };
}

export function createDefaultOvertime(base = 0): OvertimeInput {
  return {
    mode: "monthly",
    entryMode: "manual",
    base,
    followBasicSalary: true,
    hourlyRate: 0,
    monthlyDays: DEFAULT_MONTHLY_DAYS,
    dailyHours: DEFAULT_DAILY_HOURS,
    weekdayHours: 0,
    weekendHours: 0,
    holidayHours: 0,
    calendar: createDefaultCalendar(),
  };
}

export function createDefaultOvertimeSync(): OvertimeSyncSettings {
  return { enabled: false, incomeId: null };
}

/**
 * 月薪 → 小时工资：月薪 ÷ 月计薪天数 ÷ 日工时。
 * 月计薪天数或日工时非法（<= 0）时返回 0，避免除零。
 */
export function monthlyToHourly(base: number, monthlyDays: number, dailyHours: number): number {
  const days = toNonNegative(monthlyDays);
  const hours = toNonNegative(dailyHours);
  if (days <= 0 || hours <= 0) return 0;
  // 保留四位：6700 ÷ 174 = 38.5057，只留两位会让 38.51 × 1.5 变成 57.77（实际 57.7586）
  return round4(toNonNegative(base) / days / hours);
}

/**
 * 小时工资 → 月薪：时薪 × 月计薪天数 × 日工时。
 *
 * 与 monthlyToHourly 互为逆运算；参数非法时返回 0。
 *
 * 注意：时薪只有两位小数，来回折算会丢精度（5000 ÷ 174 → 28.74 → × 174 = 5000.76）。
 * 所以这里额外接受一个「当前月薪」：如果它折出来的时薪正好等于 hourlyRate，
 * 说明这个月薪和时薪本来就一致，直接用原值返回，避免每次同步都往上漂。
 */
export function hourlyToMonthly(
  hourlyRate: number,
  monthlyDays: number,
  dailyHours: number,
  currentBase?: number,
): number {
  const days = toNonNegative(monthlyDays);
  const hours = toNonNegative(dailyHours);
  if (days <= 0 || hours <= 0) return 0;
  const rate = round4(toNonNegative(hourlyRate));
  // 已在同一个值上：保留 currentBase，不让四舍五入的误差累积
  if (currentBase !== undefined && currentBase > 0 && monthlyToHourly(currentBase, days, hours) === rate) {
    return round2(currentBase);
  }
  return round2(rate * days * hours);
}

/**
 * 计算用于加班费加成的小时工资（不含倍率）。
 *
 * - 月薪模式：月薪 ÷ 月计薪天数 ÷ 日工时
 * - 时薪模式：直接使用填写的小时工资
 */
export function hourlyBaseOf(input: OvertimeInput | Pick<OvertimeInput, "mode" | "base" | "hourlyRate" | "monthlyDays" | "dailyHours">): number {
  if (input.mode === "hourly") {
    return round4(toNonNegative(input.hourlyRate));
  }
  return monthlyToHourly(input.base, input.monthlyDays, input.dailyHours);
}

/** 三档工时合计。 */
export interface TierHours {
  weekdayHours: number;
  weekendHours: number;
  holidayHours: number;
}

/** 把某一自然月的日历汇总成三档工时（不读手工填写的合计）。 */
export function summarizeCalendarHours(calendar: OvertimeCalendar): TierHours {
  const weeks = buildMonth({
    year: calendar.year,
    month: calendar.month,
    overrides: calendar.overrides,
    hours: calendar.hours,
  });
  const summary = summarizeMonth(flattenMonth(weeks));
  return {
    weekdayHours: summary.workdayHours,
    weekendHours: summary.restHours,
    holidayHours: summary.holidayHours,
  };
}

/**
 * 取出参与计算的工时。
 *
 * 手工模式直接用填的三档合计；日历模式按当月日历汇总，
 * 这样切换录入方式不会互相覆盖。
 */
export function resolveHours(input: OvertimeInput): TierHours {
  if (input.entryMode === "calendar") {
    return summarizeCalendarHours(input.calendar);
  }
  return {
    weekdayHours: toNonNegative(input.weekdayHours),
    weekendHours: toNonNegative(input.weekendHours),
    holidayHours: toNonNegative(input.holidayHours),
  };
}

export function calcOvertime(input: OvertimeInput): OvertimeResult {
  const hourlyBase = hourlyBaseOf(input);
  // 单价保留四位：基数本身就是折算值，再乘倍率只会放大误差
  const weekdayRate = round4(hourlyBase * WEEKDAY_RATE);
  const weekendRate = round4(hourlyBase * WEEKEND_RATE);
  const holidayRate = round4(hourlyBase * HOLIDAY_RATE);

  const { weekdayHours, weekendHours, holidayHours } = resolveHours(input);

  const weekdayPay = round2(weekdayRate * weekdayHours);
  const weekendPay = round2(weekendRate * weekendHours);
  const holidayPay = round2(holidayRate * holidayHours);

  return {
    hourlyBase,
    weekdayRate,
    weekendRate,
    holidayRate,
    weekdayPay,
    weekendPay,
    holidayPay,
    totalHours: round2(weekdayHours + weekendHours + holidayHours),
    totalPay: round2(weekdayPay + weekendPay + holidayPay),
  };
}

/**
 * 反推：已知工资条上的加班费，按工作日 1.5 倍折算成等价小时数。
 *
 * 用于对账——如果折算出来不是整数，说明公司用的基数或计薪天数与 21.75 不同。
 */
export function equivalentWeekdayHours(amount: number, input: OvertimeInput): number {
  const rate = hourlyBaseOf(input) * WEEKDAY_RATE;
  if (rate <= 0) return 0;
  return round2(toNonNegative(amount) / rate);
}
