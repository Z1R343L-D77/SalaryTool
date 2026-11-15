import { round2, toNonNegative } from "./money";
import {
  ANNUAL_TAX_BRACKETS,
  BASIC_DEDUCTION_PER_MONTH,
  MONTHLY_TAX_BRACKETS,
  findBracket,
  taxByBrackets,
} from "./taxTables";

/**
 * 收入项。
 *
 * 每一项都有单独的「是否计入社保基数 / 公积金基数 / 是否计税」开关，因为现实中
 * 餐补、交通补贴、差旅报销等的处理方式差异很大：
 * - 基本工资、岗位工资：一般既计入社保基数，也计税
 * - 餐补、交通补贴：通常计税，但不计入社保基数
 * - 报销类（如差旅）：一般既不计入社保基数，也不计税
 *
 * 社保基数和公积金基数分开标记，是因为不少公司两者申报口径不同：
 * 社保按上年度月平均工资，公积金只按基本工资。
 */
export interface IncomeItem {
  id: string;
  label: string;
  amount: number;
  /** 是否计入社保缴费基数 */
  includeInSocialBase: boolean;
  /** 是否计入公积金缴费基数（可与社保口径不同） */
  includeInHousingFundBase: boolean;
  /** 是否计入个人所得税应纳税所得额 */
  taxable: boolean;
}

/** 扣除项。 */
export interface DeductionItem {
  id: string;
  label: string;
  amount: number;
  /** 是否可在税前扣除（如企业年金、商业健康险等每月 200 元的专项扣除） */
  preTax: boolean;
}

/** 社保公积金的缴费基数与比例设置（均按个人缴纳部分）。 */
export interface SocialInsuranceConfig {
  /** 社保缴费基数（通常为上年月平均工资，手动填写或按收入推算） */
  socialBase: number;
  /** 社保基数下限，低于它按它缴 */
  socialBaseMin: number;
  /** 社保基数上限，高于它按它缴 */
  socialBaseMax: number;
  /** 公积金缴费基数 */
  housingFundBase: number;
  housingFundBaseMin: number;
  housingFundBaseMax: number;
  /** 养老个人比例 0.08 */
  pensionRate: number;
  /** 医疗个人比例 0.02 */
  medicalRate: number;
  /** 失业个人比例 0.005 */
  unemploymentRate: number;
  /** 公积金个人比例 0.12 */
  housingFundRate: number;
  /** 大额医疗等固定附加（元/月，个人部分） */
  medicalExtra: number;
}

/** 专项附加扣除（按月，按人）。 */
export interface SpecialDeductions {
  /** 子女教育 2000/月/子女（父母可分摊） */
  childrenEducation: number;
  /** 继续教育 400/月 或 3600/年（按 300/月 摊） */
  continuingEducation: number;
  /** 大病医疗（一般按年度汇算，此处按月填 0） */
  seriousIllness: number;
  /** 住房贷款利息 1000/月 */
  housingLoanInterest: number;
  /** 住房租金 1500/800/1100 元/月 视城市 */
  housingRent: number;
  /** 赡养老人 3000/月（独生）或分摊 */
  elderlyCare: number;
  /** 3 岁以下婴幼儿照护 2000/月/婴幼儿 */
  infantCare: number;
}

/**
 * 基本减除费用（5000 元/月）按几个月累计。
 *
 * 两种口径（国家税务总局 2020 年第 13 号公告）：
 * - calendarMonth：当年第几个月。年中首次取得工资薪金的居民个人适用，
 *   例如 7 月入职、10 月发薪，可以扣 5000 × 10。
 * - employedMonth：在本单位第几个月。年内换过工作、或之前已有工资收入时适用，
 *   避免重复享受同一段减除费用。
 */
export type BasicDeductionMode = "calendarMonth" | "employedMonth";

/** 本年度累计数据（用于累计预扣预缴）。 */
export interface YtdTotals {
  /** 本月是本年度的第几个月（1-12） */
  monthIndex: number;
  /** 截至上月的累计收入（计税口径） */
  taxableIncome: number;
  /** 截至上月的累计社保公积金个人部分 */
  socialDeduction: number;
  /** 截至上月的累计专项附加扣除 */
  specialDeduction: number;
  /** 截至上月的累计已预缴税额 */
  taxPaid: number;
  /**
   * 基本减除费用按哪种口径累计。不填时按 calendarMonth（当年第几个月）。
   *
   * 这是 2020 年第 13 号公告的核心差异：年中首次取得工资薪金的人，
   * 减除费用从当年 1 月起算，而不是从入职月起算。
   */
  basicDeductionMode?: BasicDeductionMode;
  /**
   * 在本单位的第几个月（仅 employedMonth 口径使用）。
   *
   * 例如 7 月入职、10 月发薪：monthIndex = 10，employedMonthIndex = 4，
   * 减除费用 = 5000 × 4。
   */
  employedMonthIndex?: number;
  /**
   * 为 true 时，specialDeduction 按填写的值直接用，不再按「每月金额 × 月数」推算。
   *
   * 按月记录模式下，累计值是精确加出来的，即使等于 0（例如前几个月没申报
   * 房租扣除）也不应该被自动补成推算值。
   */
  specialDeductionExact?: boolean;
  /** 仅用于界面提示：有月份记录的专项附加扣除为 0，可能是漏填 */
  hasSpecialGap?: boolean;
}

/**
 * 计算累计减除费用要乘的月数。
 *
 * employedMonth 口径下如果没填 employedMonthIndex，退回用 monthIndex，
 * 保证旧配置不会算出比原来更少的减除。
 */
export function resolveDeductionMonths(ytd: YtdTotals): number {
  const calendarMonth = Math.min(12, Math.max(1, Math.round(ytd.monthIndex) || 1));
  if (ytd.basicDeductionMode !== "employedMonth") return calendarMonth;
  const employed = Math.round(ytd.employedMonthIndex ?? 0);
  if (!Number.isFinite(employed) || employed <= 0) return calendarMonth;
  return Math.min(calendarMonth, Math.max(1, employed));
}

export interface SalaryInput {
  incomes: IncomeItem[];
  deductions: DeductionItem[];
  social: SocialInsuranceConfig;
  special: SpecialDeductions;
  ytd: YtdTotals;
  /** 年终奖（本月发放时填写），0 表示无 */
  annualBonus: number;
  /** 年终奖计税方式 */
  bonusTaxMode: "separate" | "combined";
}

export interface SocialBreakdown {
  pension: number;
  medical: number;
  unemployment: number;
  housingFund: number;
  medicalExtra: number;
  total: number;
}

export interface SalaryResult {
  // —— 收入 ——
  grossIncome: number;
  taxableIncome: number;
  socialBaseUsed: number;
  housingFundBaseUsed: number;

  // —— 社保公积金 ——
  social: SocialBreakdown;

  // —— 个税 ——
  specialDeductionTotal: number;
  cumulativeTaxable: number;
  cumulativeTax: number;
  taxThisMonth: number;
  effectiveTaxRate: number;

  // —— 年终奖 ——
  bonusGross: number;
  bonusTax: number;

  // —— 到手 ——
  netPay: number;

  // —— 明细行（用于表格展示）——
  rows: ResultRow[];
}

export interface ResultRow {
  key: string;
  label: string;
  amount: number;
  kind: "income" | "social" | "deduction" | "tax" | "total";
  hint?: string;
}

/** 计算某项收入是否计入社保基数（需要基数为按比例时）。 */
function sumIncomes(list: readonly IncomeItem[], pick: (i: IncomeItem) => boolean): number {
  return round2(
    list
      .filter((item) => item.amount > 0 && pick(item))
      .reduce((total, item) => total + toNonNegative(item.amount), 0),
  );
}

export function sumSpecialDeductions(special: SpecialDeductions): number {
  return round2(
    toNonNegative(special.childrenEducation) +
      toNonNegative(special.continuingEducation) +
      toNonNegative(special.seriousIllness) +
      toNonNegative(special.housingLoanInterest) +
      toNonNegative(special.housingRent) +
      toNonNegative(special.elderlyCare) +
      toNonNegative(special.infantCare),
  );
}

/** 在上下限内取缴费基数。 */
export function clampBase(base: number, min: number, max: number): number {
  const value = toNonNegative(base);
  const lower = toNonNegative(min);
  const upper = max > 0 ? toNonNegative(max) : Number.POSITIVE_INFINITY;
  return round2(Math.min(Math.max(value, lower), upper));
}

export function calcSocial(social: SocialInsuranceConfig): SocialBreakdown {
  const socialBase = clampBase(social.socialBase, social.socialBaseMin, social.socialBaseMax);
  const fundBase = clampBase(social.housingFundBase, social.housingFundBaseMin, social.housingFundBaseMax);

  const pension = round2(socialBase * toNonNegative(social.pensionRate));
  const medical = round2(socialBase * toNonNegative(social.medicalRate));
  const unemployment = round2(socialBase * toNonNegative(social.unemploymentRate));
  const housingFund = round2(fundBase * toNonNegative(social.housingFundRate));
  const medicalExtra = round2(toNonNegative(social.medicalExtra));

  return {
    pension,
    medical,
    unemployment,
    housingFund,
    medicalExtra,
    total: round2(pension + medical + unemployment + housingFund + medicalExtra),
  };
}

/**
 * 年终奖单独计税：奖金 ÷ 12 查月度税率表，税额 = 奖金 × 税率 − 速算扣除数。
 */
export function calcBonusTaxSeparate(bonus: number): number {
  const amount = toNonNegative(bonus);
  if (amount === 0) return 0;
  const bracket = findBracket(amount / 12, MONTHLY_TAX_BRACKETS);
  return round2(Math.max(0, amount * bracket.rate - bracket.quickDeduction));
}

/**
 * 计算当月工资到手。
 *
 * 个税采用累计预扣预缴：
 * 累计应纳税所得额 = 累计收入 — 累计减除费用(5000×月数) — 累计专项扣除(社保公积金)
 *                  — 累计专项附加扣除 — 累计其他扣除
 * 本月应预扣 = 累计应纳税额 — 截至上月已预缴税额
 */
export function calcSalary(input: SalaryInput): SalaryResult {
  const incomes = input.incomes;
  const grossIncome = sumIncomes(incomes, () => true);
  const taxableIncome = sumIncomes(incomes, (item) => item.taxable);

  const social = calcSocial(input.social);
  const specialDeductionTotal = sumSpecialDeductions(input.special);

  // 税前其他扣除（如企业年金个人部分）
  const preTaxDeductions = round2(
    input.deductions
      .filter((item) => item.preTax && item.amount > 0)
      .reduce((total, item) => total + toNonNegative(item.amount), 0),
  );
  const afterTaxDeductions = round2(
    input.deductions
      .filter((item) => !item.preTax && item.amount > 0)
      .reduce((total, item) => total + toNonNegative(item.amount), 0),
  );

  const monthIndex = Math.min(12, Math.max(1, Math.round(input.ytd.monthIndex || 1)));
  const ytd = input.ytd;

  // 累计口径
  const cumulativeIncome = round2(toNonNegative(ytd.taxableIncome) + taxableIncome);
  // 减除费用按月数累计：年中首次取得工资薪金的人可追溯到当年 1 月（5000 × 当年月份数）
  const deductionMonths = resolveDeductionMonths(ytd);
  const cumulativeBasicDeduction = round2(BASIC_DEDUCTION_PER_MONTH * deductionMonths);
  const cumulativeSocial = round2(toNonNegative(ytd.socialDeduction) + social.total + preTaxDeductions);
  // 用户没填「截至上月累计专项附加扣除」时，按当前每月金额 × 已过月数自动补上。
  // 按月记录模式下累计值是精确的（specialDeductionExact），即使为 0 也照用。
  const priorSpecialDeduction =
    ytd.specialDeductionExact || ytd.specialDeduction > 0
      ? toNonNegative(ytd.specialDeduction)
      : round2(specialDeductionTotal * (monthIndex - 1));
  const cumulativeSpecial = round2(priorSpecialDeduction + specialDeductionTotal);

  let cumulativeTaxable = round2(
    cumulativeIncome - cumulativeBasicDeduction - cumulativeSocial - cumulativeSpecial,
  );
  if (cumulativeTaxable < 0) cumulativeTaxable = 0;

  let cumulativeTax = taxByBrackets(cumulativeTaxable, ANNUAL_TAX_BRACKETS);

  // 年终奖
  const bonusGross = round2(toNonNegative(input.annualBonus));
  let bonusTax = 0;
  let bonusCombinedTaxable = 0;
  if (bonusGross > 0) {
    if (input.bonusTaxMode === "separate") {
      bonusTax = calcBonusTaxSeparate(bonusGross);
    } else {
      // 并入综合所得：加入到累计应纳税所得额中重新计算
      bonusCombinedTaxable = bonusGross;
      cumulativeTaxable = round2(cumulativeTaxable + bonusGross);
      cumulativeTax = taxByBrackets(cumulativeTaxable, ANNUAL_TAX_BRACKETS);
    }
  }

  const taxPaid = toNonNegative(ytd.taxPaid);
  const taxThisMonth = Math.max(0, round2(cumulativeTax - taxPaid)) + bonusTax;

  const netPay = round2(
    grossIncome +
      bonusGross -
      social.total -
      preTaxDeductions -
      afterTaxDeductions -
      taxThisMonth,
  );

  const effectiveTaxRate = taxableIncome + bonusCombinedTaxable > 0
    ? taxThisMonth / (taxableIncome + bonusCombinedTaxable)
    : 0;

  const rows: ResultRow[] = [];
  for (const item of incomes) {
    rows.push({
      key: `income-${item.id}`,
      label: item.label,
      amount: round2(item.amount),
      kind: "income",
      hint: describeIncomeFlags(item),
    });
  }
  if (bonusGross > 0) {
    rows.push({
      key: "income-bonus",
      label: "年终奖",
      amount: bonusGross,
      kind: "income",
      hint: input.bonusTaxMode === "separate" ? "单独计税" : "并入综合所得",
    });
  }  rows.push(
    { key: "social-pension", label: "养老保险（个人）", amount: -social.pension, kind: "social" },
    { key: "social-medical", label: "医疗保险（个人）", amount: -social.medical, kind: "social" },
    { key: "social-unemployment", label: "失业保险（个人）", amount: -social.unemployment, kind: "social" },
  );
  if (social.medicalExtra > 0) {
    rows.push({ key: "social-medical-extra", label: "大额医疗互助", amount: -social.medicalExtra, kind: "social" });
  }
  rows.push({ key: "social-fund", label: "住房公积金（个人）", amount: -social.housingFund, kind: "social" });

  for (const item of input.deductions) {
    if (item.amount > 0) {
      rows.push({
        key: `deduction-${item.id}`,
        label: item.label,
        amount: -round2(item.amount),
        kind: "deduction",
        hint: item.preTax ? "税前扣除" : "税后扣除",
      });
    }
  }
  rows.push({ key: "tax", label: "本月个人所得税", amount: -taxThisMonth, kind: "tax" });
  rows.push({ key: "net", label: "实发到手", amount: netPay, kind: "total" });

  return {
    grossIncome,
    taxableIncome,
    socialBaseUsed: clampBase(input.social.socialBase, input.social.socialBaseMin, input.social.socialBaseMax),
    housingFundBaseUsed: clampBase(input.social.housingFundBase, input.social.housingFundBaseMin, input.social.housingFundBaseMax),
    social,
    specialDeductionTotal,
    cumulativeTaxable,
    cumulativeTax,
    taxThisMonth,
    effectiveTaxRate,
    bonusGross,
    bonusTax,
    netPay,
    rows,
  };
}

/**
 * 根据收入项自动推算社保/公积金缴费基数：只统计标记为「计入基数」的收入。
 */
export function suggestSocialBase(incomes: readonly IncomeItem[]): number {
  return sumIncomes(incomes, (item) => item.includeInSocialBase);
}

export function suggestHousingFundBase(incomes: readonly IncomeItem[]): number {
  return sumIncomes(incomes, (item) => item.includeInHousingFundBase);
}

/** 收入项的标记摘要，用于明细展示。 */
export function describeIncomeFlags(item: IncomeItem): string {
  const flags: string[] = [];
  if (item.includeInSocialBase) flags.push("社保");
  if (item.includeInHousingFundBase) flags.push("公积金");
  const base = flags.length ? `计入${flags.join("+")}` : "不计基数";
  return `${base} · ${item.taxable ? "计税" : "不计税"}`;
}
