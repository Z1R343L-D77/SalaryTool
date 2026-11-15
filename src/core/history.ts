import type { YtdTotals } from "./calculator";
import { round2, toNonNegative } from "./money";

/**
 * 按月记录。
 *
 * 累计预扣预缴需要「截至上月」的累计数，手工每月现算容易错。
 * 把每个月工资条上的实际数字记下来，累计值就能自动加出来。
 */
export interface MonthRecord {
  id: string;
  /** 本年度第几个月（1-12） */
  month: number;
  /** 该月计税收入（工资条「计税口径」的应发） */
  taxableIncome: number;
  /** 该月社保公积金个人部分合计 */
  socialDeduction: number;
  /** 该月专项附加扣除（按当月适用金额填） */
  specialDeduction: number;
  /** 该月实际被扣的个税（工资条上的数，不是算出来的） */
  taxPaid: number;
  /** 备注，例如「补报租金扣除」 */
  note: string;
}

/** 累计口径的字段名，用于空记录初始化。 */
export type YtdField = keyof Pick<
  YtdTotals,
  "taxableIncome" | "socialDeduction" | "specialDeduction" | "taxPaid"
>;

/**
 * 把某月之前（不含本月）的记录汇总成累计数。
 *
 * 同一个月只取最后一条，方便用户重复记录后修正。
 */
export function computeYtdFromMonths(
  months: readonly MonthRecord[],
  monthIndex: number,
): YtdTotals {
  const current = Math.min(12, Math.max(1, Math.round(monthIndex) || 1));
  const latest = new Map<number, MonthRecord>();
  for (const record of months) {
    const month = Math.min(12, Math.max(1, Math.round(record.month)));
    if (month >= current) continue;
    latest.set(month, record);
  }

  let taxableIncome = 0;
  let socialDeduction = 0;
  let specialDeduction = 0;
  let taxPaid = 0;
  let hasSpecialGap = false;

  for (const month of [...latest.keys()].sort((a, b) => a - b)) {
    const record = latest.get(month)!;
    taxableIncome += toNonNegative(record.taxableIncome);
    socialDeduction += toNonNegative(record.socialDeduction);
    specialDeduction += toNonNegative(record.specialDeduction);
    taxPaid += toNonNegative(record.taxPaid);
    // 专项附加扣除项有记录但金额为 0，可能是漏填
    if (toNonNegative(record.specialDeduction) === 0) hasSpecialGap = true;
  }

  return {
    monthIndex: current,
    taxableIncome: round2(taxableIncome),
    socialDeduction: round2(socialDeduction),
    specialDeduction: round2(specialDeduction),
    taxPaid: round2(taxPaid),
    hasSpecialGap,
  };
}

/** 找出本月之前缺记录的月份，用于提示。 */
export function findMissingMonths(months: readonly MonthRecord[], monthIndex: number): number[] {
  const current = Math.min(12, Math.max(1, Math.round(monthIndex) || 1));
  const recorded = new Set(months.map((record) => Math.round(record.month)));
  const missing: number[] = [];
  for (let month = 1; month < current; month += 1) {
    if (!recorded.has(month)) missing.push(month);
  }
  return missing;
}

/** 按月份排序，供界面展示。 */
export function sortMonths(months: readonly MonthRecord[]): MonthRecord[] {
  return [...months].sort((a, b) => a.month - b.month);
}
