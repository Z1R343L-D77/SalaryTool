/**
 * 个人所得税税率表。
 *
 * 工资薪金采用「累计预扣预缴」：每个纳税年度内，累计应纳税所得额适用
 * 《个人所得税预扣率表一》（综合所得年度税率表），再减去速算扣除数。
 *
 * 年终奖选择「单独计税」时，按奖金 ÷ 12 的商查「按月换算后的综合所得税率表」。
 *
 * 数据来源：财政部 税务总局公告 2018 年第 98 号及后续延续政策。
 */

export interface TaxBracket {
  /** 级数 1-7 */
  level: number;
  /** 本级下限（含） */
  lower: number;
  /** 本级上限（含），null 表示无上限 */
  upper: number | null;
  /** 税率，0.03 表示 3% */
  rate: number;
  /** 速算扣除数（元） */
  quickDeduction: number;
}

/** 综合所得年度税率表（累计预扣预缴使用）。 */
export const ANNUAL_TAX_BRACKETS: readonly TaxBracket[] = [
  { level: 1, lower: 0, upper: 36000, rate: 0.03, quickDeduction: 0 },
  { level: 2, lower: 36000, upper: 144000, rate: 0.1, quickDeduction: 2520 },
  { level: 3, lower: 144000, upper: 300000, rate: 0.2, quickDeduction: 16920 },
  { level: 4, lower: 300000, upper: 420000, rate: 0.25, quickDeduction: 31920 },
  { level: 5, lower: 420000, upper: 660000, rate: 0.3, quickDeduction: 52920 },
  { level: 6, lower: 660000, upper: 960000, rate: 0.35, quickDeduction: 85920 },
  { level: 7, lower: 960000, upper: null, rate: 0.45, quickDeduction: 181920 },
];

/** 按月换算后的综合所得税率表（全年一次性奖金单独计税使用）。 */
export const MONTHLY_TAX_BRACKETS: readonly TaxBracket[] = [
  { level: 1, lower: 0, upper: 3000, rate: 0.03, quickDeduction: 0 },
  { level: 2, lower: 3000, upper: 12000, rate: 0.1, quickDeduction: 210 },
  { level: 3, lower: 12000, upper: 25000, rate: 0.2, quickDeduction: 1410 },
  { level: 4, lower: 25000, upper: 35000, rate: 0.25, quickDeduction: 2660 },
  { level: 5, lower: 35000, upper: 55000, rate: 0.3, quickDeduction: 4410 },
  { level: 6, lower: 55000, upper: 80000, rate: 0.35, quickDeduction: 7160 },
  { level: 7, lower: 80000, upper: null, rate: 0.45, quickDeduction: 15160 },
];

/** 每月基本减除费用（起征点）。 */
export const BASIC_DEDUCTION_PER_MONTH = 5000;

/** 在税率表中定位某金额所属的级距。 */
export function findBracket(
  amount: number,
  table: readonly TaxBracket[] = ANNUAL_TAX_BRACKETS,
): TaxBracket {
  const value = Math.max(0, amount);
  for (const bracket of table) {
    if (bracket.upper === null || value <= bracket.upper) return bracket;
  }
  return table[table.length - 1];
}

/**
 * 按「应纳税额 = 应纳税所得额 × 税率 − 速算扣除数」计算税款。
 * 传入的应纳税所得额应为正数；为负时按 0 处理。
 */
export function taxByBrackets(
  taxable: number,
  table: readonly TaxBracket[] = ANNUAL_TAX_BRACKETS,
): number {
  const amount = Math.max(0, taxable);
  if (amount === 0) return 0;
  const bracket = findBracket(amount, table);
  const tax = amount * bracket.rate - bracket.quickDeduction;
  return Math.max(0, Math.round((tax + Number.EPSILON) * 100) / 100);
}
