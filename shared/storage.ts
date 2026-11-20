import type { DeductionItem, IncomeItem } from "./calculator";
import type { BasicDeductionMode } from "./calculator";
import { findCityPolicy } from "./cityPolicies";
import type { SalaryState } from "./defaults";
import { createDefaultState } from "./defaults";
import type { MonthRecord } from "./history";
import { sortMonths } from "./history";
import type { DayType } from "./calendar";
import { MAX_YEAR, MIN_YEAR } from "./calendar";
import type { OvertimeCalendar, OvertimeEntryMode, OvertimeInput, OvertimeSyncSettings } from "./overtime";
import { createDefaultCalendar, createDefaultOvertime, createDefaultOvertimeSync } from "./overtime";
import type { MealAllowanceInput, MealCalendar, MealCounts, MealRates, MealScene, MealSyncSettings } from "./mealAllowance";
import {
  createDefaultMealAllowance,
  createDefaultMealSync,
  emptyMealCounts,
  MEAL_SCENES,
} from "./mealAllowance";
import { round2, toAmount, toNonNegative } from "./money";

/**
 * 本地持久化与配置导入。
 *
 * 工资数据敏感，只存本机 localStorage，不上传。
 * 导入/读取时统一走 normalizeState：缺字段用默认值补齐、类型不对就纠正，
 * 避免手工编辑过的 JSON 或旧版本数据把界面搞崩。
 */

const STORAGE_KEY = "salarytool.state.v1";

function pickString(value: unknown, fallback: string): string {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

/** 数字兜底：接受数字或数字字符串，非法值用 fallback。 */
function pickNumber(value: unknown, fallback: number): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : fallback;
  return toAmount(value, fallback);
}

function normalizeIncome(raw: unknown, index: number): IncomeItem | null {
  if (!raw || typeof raw !== "object") return null;
  const item = raw as Record<string, unknown>;
  const includeInSocialBase = item.includeInSocialBase === undefined
    ? true
    : Boolean(item.includeInSocialBase);
  return {
    id: pickString(item.id, `income-${index + 1}`),
    label: pickString(item.label, "收入"),
    amount: round2(toNonNegative(item.amount)),
    includeInSocialBase,
    // 旧数据没有这个字段时，沿用社保口径，保持行为不变
    includeInHousingFundBase: item.includeInHousingFundBase === undefined
      ? includeInSocialBase
      : Boolean(item.includeInHousingFundBase),
    // 没写 taxable 时按「计税」处理，与新增收入项的默认一致
    taxable: item.taxable === undefined ? true : Boolean(item.taxable),
  };
}

function normalizeDeduction(raw: unknown, index: number): DeductionItem | null {
  if (!raw || typeof raw !== "object") return null;
  const item = raw as Record<string, unknown>;
  return {
    id: pickString(item.id, `deduction-${index + 1}`),
    label: pickString(item.label, "扣除"),
    amount: round2(toNonNegative(item.amount)),
    preTax: Boolean(item.preTax),
  };
}

function normalizeMonth(raw: unknown, index: number): MonthRecord | null {
  if (!raw || typeof raw !== "object") return null;
  const item = raw as Record<string, unknown>;
  const month = Math.min(12, Math.max(1, Math.round(pickNumber(item.month, 1))));
  return {
    id: pickString(item.id, `month-${month}-${index + 1}`),
    month,
    taxableIncome: round2(toNonNegative(item.taxableIncome)),
    socialDeduction: round2(toNonNegative(item.socialDeduction)),
    specialDeduction: round2(toNonNegative(item.specialDeduction)),
    taxPaid: round2(toNonNegative(item.taxPaid)),
    note: typeof item.note === "string" ? item.note : "",
  };
}

function normalizeCalendar(raw: unknown): OvertimeCalendar {
  const base = createDefaultCalendar();
  if (!raw || typeof raw !== "object") return base;
  const item = raw as Record<string, unknown>;

  const hours: Record<string, number> = {};
  if (item.hours && typeof item.hours === "object") {
    for (const [key, value] of Object.entries(item.hours as Record<string, unknown>)) {
      const amount = round2(toNonNegative(value));
      if (amount > 0) hours[key] = amount;
    }
  }

  const overrides: Record<string, DayType> = {};
  if (item.overrides && typeof item.overrides === "object") {
    for (const [key, value] of Object.entries(item.overrides as Record<string, unknown>)) {
      if (value === "workday" || value === "rest" || value === "holiday") {
        overrides[key] = value;
      }
    }
  }

  return {
    year: Math.min(MAX_YEAR, Math.max(MIN_YEAR, Math.round(pickNumber(item.year, base.year)))),
    month: Math.min(12, Math.max(1, Math.round(pickNumber(item.month, base.month)))),
    hours,
    overrides,
  };
}

function normalizeOvertime(raw: unknown): OvertimeInput {
  const base = createDefaultOvertime();
  if (!raw || typeof raw !== "object") return base;
  const item = raw as Record<string, unknown>;

  // 旧数据没有 entryMode 时按手工模式处理，行为不变
  const entryMode: OvertimeEntryMode =
    item.entryMode === "calendar" ? "calendar" : "manual";

  let legacyBase: OvertimeInput["mode"] = item.mode === "hourly" ? "hourly" : "monthly";
  let legacyFollow = item.followBasicSalary === undefined ? true : Boolean(item.followBasicSalary);

  return {
    mode: legacyBase,
    entryMode,
    base: pickNumber(item.base, base.base),
    followBasicSalary: legacyFollow,
    hourlyRate: pickNumber(item.hourlyRate, base.hourlyRate),
    // 月计薪天数和日工时必须是正数，否则折算会除零
    monthlyDays: Math.max(1, pickNumber(item.monthlyDays, base.monthlyDays)),
    dailyHours: Math.max(1, pickNumber(item.dailyHours, base.dailyHours)),
    weekdayHours: round2(toNonNegative(item.weekdayHours)),
    weekendHours: round2(toNonNegative(item.weekendHours)),
    holidayHours: round2(toNonNegative(item.holidayHours)),
    calendar: normalizeCalendar(item.calendar ?? raw),
  };
}

function normalizeOvertimeSync(raw: unknown): OvertimeSyncSettings {
  const base = createDefaultOvertimeSync();
  if (!raw || typeof raw !== "object") return base;
  const item = raw as Record<string, unknown>;
  return {
    enabled: Boolean(item.enabled),
    incomeId: typeof item.incomeId === "string" && item.incomeId ? item.incomeId : null,
  };
}

/** 把任意值整理成长度为 3 的餐次计数（0 或正整数）。 */
function normalizeMealCounts(raw: unknown, fallback: MealCounts): MealCounts {
  if (!raw || typeof raw !== "object") return { ...fallback };
  const item = raw as Record<string, unknown>;
  return {
    breakfast: round2(toNonNegative(item.breakfast ?? fallback.breakfast)),
    lunch: round2(toNonNegative(item.lunch ?? fallback.lunch)),
    dinner: round2(toNonNegative(item.dinner ?? fallback.dinner)),
  };
}

function normalizeMealRates(raw: unknown): MealRates {
  const base = createDefaultMealAllowance().rates;
  if (!raw || typeof raw !== "object") return base;
  const item = raw as Record<string, unknown>;
  return {
    workday: normalizeMealCounts(item.workday, base.workday),
    weekend: normalizeMealCounts(item.weekend, base.weekend),
    trip: normalizeMealCounts(item.trip, base.trip),
  };
}

function normalizeMealCalendar(raw: unknown): MealCalendar {
  const base = createDefaultMealAllowance().calendar;
  if (!raw || typeof raw !== "object") return base;
  const item = raw as Record<string, unknown>;

  const meals: Record<string, MealCounts> = {};
  if (item.meals && typeof item.meals === "object") {
    for (const [key, value] of Object.entries(item.meals as Record<string, unknown>)) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) continue;
      const counts = normalizeMealCounts(value, emptyMealCounts());
      // 一顿都没吃的条目不保留，避免日历里堆满空记录
      if (counts.breakfast + counts.lunch + counts.dinner > 0) meals[key] = counts;
    }
  }

  const trips: Record<string, boolean> = {};
  if (item.trips && typeof item.trips === "object") {
    for (const [key, value] of Object.entries(item.trips as Record<string, unknown>)) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) continue;
      if (value === true) trips[key] = true;
    }
  }

  const overrides: Record<string, DayType> = {};
  if (item.overrides && typeof item.overrides === "object") {
    for (const [key, value] of Object.entries(item.overrides as Record<string, unknown>)) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) continue;
      if (value === "workday" || value === "rest" || value === "holiday") {
        overrides[key] = value;
      }
    }
  }

  return {
    year: Math.min(MAX_YEAR, Math.max(MIN_YEAR, Math.round(pickNumber(item.year, base.year)))),
    month: Math.min(12, Math.max(1, Math.round(pickNumber(item.month, base.month)))),
    meals,
    trips,
    overrides,
  };
}

function normalizeMealAllowance(raw: unknown): MealAllowanceInput {
  const base = createDefaultMealAllowance();
  if (!raw || typeof raw !== "object") return base;
  const item = raw as Record<string, unknown>;

  const manualRaw = (item.manual && typeof item.manual === "object"
    ? item.manual
    : {}) as Record<string, unknown>;
  const manual = {} as Record<MealScene, MealCounts>;
  for (const scene of MEAL_SCENES) {
    manual[scene] = normalizeMealCounts(manualRaw[scene], emptyMealCounts());
  }

  return {
    entryMode: item.entryMode === "calendar" ? "calendar" : "manual",
    rates: normalizeMealRates(item.rates),
    manual,
    calendar: normalizeMealCalendar(item.calendar),
  };
}

function normalizeMealSync(raw: unknown): MealSyncSettings {
  const base = createDefaultMealSync();
  if (!raw || typeof raw !== "object") return base;
  const item = raw as Record<string, unknown>;
  return {
    enabled: Boolean(item.enabled),
    incomeId: typeof item.incomeId === "string" && item.incomeId ? item.incomeId : null,
  };
}

/**
 * 把任意来源的数据整理成完整的 SalaryState。
 *
 * 配置文件、备份文件、localStorage 里的旧数据都走这里，保证结构一致。
 */
export function normalizeState(input: unknown): SalaryState {
  const base = createDefaultState();
  if (!input || typeof input !== "object") return base;

  const raw = input as Record<string, unknown>;
  const social = (raw.social && typeof raw.social === "object" ? raw.social : {}) as Record<string, unknown>;
  const special = (raw.special && typeof raw.special === "object" ? raw.special : {}) as Record<string, unknown>;
  const ytd = (raw.ytd && typeof raw.ytd === "object" ? raw.ytd : {}) as Record<string, unknown>;

  const incomes = Array.isArray(raw.incomes)
    ? raw.incomes.map(normalizeIncome).filter((item): item is IncomeItem => item !== null)
    : [];
  const deductions = Array.isArray(raw.deductions)
    ? raw.deductions.map(normalizeDeduction).filter((item): item is DeductionItem => item !== null)
    : [];
  const months = Array.isArray(raw.months)
    ? raw.months.map(normalizeMonth).filter((item): item is MonthRecord => item !== null)
    : [];

  const monthIndex = Math.min(
    12,
    Math.max(1, Math.round(pickNumber(ytd.monthIndex, base.ytd.monthIndex))),
  );
  // 减除费用口径：旧配置没有这个字段时按「当年第几个月」处理（现行主流口径）
  const basicDeductionMode: BasicDeductionMode =
    ytd.basicDeductionMode === "employedMonth" ? "employedMonth" : "calendarMonth";
  const rawEmployed = Math.round(pickNumber(ytd.employedMonthIndex, 0));
  const employedMonthIndex = rawEmployed > 0
    ? Math.min(monthIndex, Math.max(1, rawEmployed))
    : undefined;

  // 没显式写基数模式时：有明确基数就当手动，否则沿用默认
  const hasExplicitBase = pickNumber(social.socialBase, 0) > 0;
  const hasExplicitFundBase = pickNumber(social.housingFundBase, 0) > 0;
  const socialBaseMode =
    raw.socialBaseMode === "auto" || raw.socialBaseMode === "manual"
      ? raw.socialBaseMode
      : hasExplicitBase
        ? "manual"
        : base.socialBaseMode;
  // 旧配置只有一个 socialBaseMode，没有单独写公积金模式时沿用社保的模式
  const housingFundBaseMode =
    raw.housingFundBaseMode === "auto" || raw.housingFundBaseMode === "manual"
      ? raw.housingFundBaseMode
      : (raw.socialBaseMode === "auto" || raw.socialBaseMode === "manual")
        ? raw.socialBaseMode
        : hasExplicitFundBase
          ? "manual"
          : base.housingFundBaseMode;

  return {
    cityId: findCityPolicy(pickString(raw.cityId, base.cityId)).id,
    socialBaseMode,
    housingFundBaseMode,
    incomes: incomes.length ? incomes : base.incomes,
    deductions,
    social: {
      socialBase: pickNumber(social.socialBase, base.social.socialBase),
      socialBaseMin: pickNumber(social.socialBaseMin, base.social.socialBaseMin),
      socialBaseMax: pickNumber(social.socialBaseMax, base.social.socialBaseMax),
      housingFundBase: pickNumber(social.housingFundBase, base.social.housingFundBase),
      housingFundBaseMin: pickNumber(social.housingFundBaseMin, base.social.housingFundBaseMin),
      housingFundBaseMax: pickNumber(social.housingFundBaseMax, base.social.housingFundBaseMax),
      pensionRate: pickNumber(social.pensionRate, base.social.pensionRate),
      medicalRate: pickNumber(social.medicalRate, base.social.medicalRate),
      unemploymentRate: pickNumber(social.unemploymentRate, base.social.unemploymentRate),
      housingFundRate: pickNumber(social.housingFundRate, base.social.housingFundRate),
      medicalExtra: pickNumber(social.medicalExtra, base.social.medicalExtra),
    },
    special: {
      childrenEducation: pickNumber(special.childrenEducation, base.special.childrenEducation),
      continuingEducation: pickNumber(special.continuingEducation, base.special.continuingEducation),
      seriousIllness: pickNumber(special.seriousIllness, base.special.seriousIllness),
      housingLoanInterest: pickNumber(special.housingLoanInterest, base.special.housingLoanInterest),
      housingRent: pickNumber(special.housingRent, base.special.housingRent),
      elderlyCare: pickNumber(special.elderlyCare, base.special.elderlyCare),
      infantCare: pickNumber(special.infantCare, base.special.infantCare),
    },
    ytdMode: raw.ytdMode === "records" ? "records" : "manual",
    ytd: {
      monthIndex,
      taxableIncome: round2(toNonNegative(ytd.taxableIncome)),
      socialDeduction: round2(toNonNegative(ytd.socialDeduction)),
      specialDeduction: round2(toNonNegative(ytd.specialDeduction)),
      taxPaid: round2(toNonNegative(ytd.taxPaid)),
      basicDeductionMode,
      employedMonthIndex,
      specialDeductionExact: raw.ytdMode === "records" ? true : undefined,
    },
    months: sortMonths(months),
    annualBonus: round2(toNonNegative(raw.annualBonus)),
    bonusTaxMode: raw.bonusTaxMode === "combined" ? "combined" : "separate",
    overtime: normalizeOvertime(raw.overtime),
    overtimeSync: normalizeOvertimeSync(raw.overtimeSync),
    mealAllowance: normalizeMealAllowance(raw.mealAllowance),
    mealSync: normalizeMealSync(raw.mealSync),
  };
}

export function loadState(): SalaryState | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return normalizeState(JSON.parse(raw));
  } catch {
    return null;
  }
}

export function saveState(state: SalaryState): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch {
    // 存储不可用（隐私模式 / 配额满）时静默失败，不影响计算
  }
}

export function clearState(): void {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // ignore
  }
}

/** 导出为 JSON 字符串，方便备份或直接分享。 */
export function exportState(state: SalaryState): string {
  return JSON.stringify(state, null, 2);
}
