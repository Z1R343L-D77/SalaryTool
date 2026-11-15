import type { CitySocialPolicy } from "./cityPolicies";
import { findCityPolicy } from "./cityPolicies";
import type {
  DeductionItem,
  IncomeItem,
  SalaryInput,
  SalaryResult,
  SocialInsuranceConfig,
  SpecialDeductions,
  YtdTotals,
} from "./calculator";
import {
  calcSalary,
  clampBase,
  suggestHousingFundBase,
  suggestSocialBase,
  sumSpecialDeductions,
} from "./calculator";
import type { MonthRecord } from "./history";
import { computeYtdFromMonths, findMissingMonths } from "./history";
import type { OvertimeInput, OvertimeSyncSettings } from "./overtime";
import { createDefaultOvertime, createDefaultOvertimeSync } from "./overtime";

/**
 * 基数模式：auto 按收入自动推算，manual 手动填写。
 * 社保和公积金各自独立，因为不少公司两者的申报口径不同。
 */
export type BaseMode = "auto" | "manual";

/** 累计数据的来源：manual 手填，records 按月记录自动累加。 */
export type YtdMode = "manual" | "records";

export interface SalaryState {
  cityId: string;
  socialBaseMode: BaseMode;
  housingFundBaseMode: BaseMode;
  incomes: IncomeItem[];
  deductions: DeductionItem[];
  social: SocialInsuranceConfig;
  special: SpecialDeductions;
  /** manual 模式下直接用 ytd，records 模式下由 months 累加得到 */
  ytdMode: YtdMode;
  ytd: YtdTotals;
  /** 按月记录，用于自动累计 */
  months: MonthRecord[];
  annualBonus: number;
  bonusTaxMode: "separate" | "combined";
  /** 加班费计算器的输入，持久化保存，切换栏目不会丢 */
  overtime: OvertimeInput;
  /** 加班费与收入项的联动设置 */
  overtimeSync: OvertimeSyncSettings;
}

let seq = 0;
/** 生成一个稳定的 id（只在新建条目时调用）。 */
export function uid(prefix: string): string {
  seq += 1;
  return `${prefix}-${Date.now().toString(36)}-${seq}`;
}

/** 常用收入项模板，新增时供用户挑选。 */
export const INCOME_PRESETS: ReadonlyArray<
  Pick<IncomeItem, "label" | "includeInSocialBase" | "includeInHousingFundBase" | "taxable">
> = [
  { label: "基本工资", includeInSocialBase: true, includeInHousingFundBase: true, taxable: true },
  { label: "岗位工资", includeInSocialBase: true, includeInHousingFundBase: true, taxable: true },
  { label: "绩效工资", includeInSocialBase: true, includeInHousingFundBase: false, taxable: true },
  { label: "综合补贴", includeInSocialBase: true, includeInHousingFundBase: false, taxable: true },
  { label: "租房补贴", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true },
  { label: "餐补", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true },
  { label: "交通补贴", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true },
  { label: "通讯补贴", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true },
  { label: "全勤奖", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true },
  // 加班费 = 工时 × 倍率算出来的浮动金额，可由加班费计算器同步；
  // 加班补助 = 公司另发的固定补贴，两者是独立的收入项，不要合并。
  { label: "加班费", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true },
  { label: "加班补助", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true },
  { label: "报销（非工资）", includeInSocialBase: false, includeInHousingFundBase: false, taxable: false },
];

export const DEDUCTION_PRESETS: ReadonlyArray<Pick<DeductionItem, "label" | "preTax">> = [
  { label: "企业年金（个人）", preTax: true },
  { label: "商业健康险", preTax: true },
  { label: "迟到/事假扣款", preTax: false },
  { label: "其他扣款", preTax: false },
];

type IncomePreset = Pick<IncomeItem, "label" | "includeInSocialBase" | "includeInHousingFundBase" | "taxable">;

function makeIncome(preset: IncomePreset, amount = 0): IncomeItem {
  return { id: uid("income"), amount, ...preset };
}

/** 首次启动 / 重置时的示例数据，方便用户直接看到效果。 */
export function createDefaultState(): SalaryState {
  const city = findCityPolicy("beijing");
  const incomes: IncomeItem[] = [
    makeIncome(INCOME_PRESETS[0], 15000),
    makeIncome(INCOME_PRESETS[4], 2000),
    makeIncome(INCOME_PRESETS[5], 660),
  ];
  return {
    cityId: city.id,
    socialBaseMode: "auto",
    housingFundBaseMode: "auto",
    incomes,
    deductions: [],
    social: socialConfigFromCity(city),
    special: {
      childrenEducation: 0,
      continuingEducation: 0,
      seriousIllness: 0,
      housingLoanInterest: 0,
      housingRent: 1500,
      elderlyCare: 0,
      infantCare: 0,
    },
    ytdMode: "manual",
    ytd: { monthIndex: 1, taxableIncome: 0, socialDeduction: 0, specialDeduction: 0, taxPaid: 0 },
    months: [],
    annualBonus: 0,
    bonusTaxMode: "separate",
    overtime: createDefaultOvertime(),
    overtimeSync: createDefaultOvertimeSync(),
  };
}

export function socialConfigFromCity(
  city: CitySocialPolicy,
  previousSocialBase?: number,
  previousFundBase?: number,
): SocialInsuranceConfig {
  return {
    socialBase: previousSocialBase ?? city.socialBaseMin,
    socialBaseMin: city.socialBaseMin,
    socialBaseMax: city.socialBaseMax,
    housingFundBase: previousFundBase ?? city.housingFundBaseMin,
    housingFundBaseMin: city.housingFundBaseMin,
    housingFundBaseMax: city.housingFundBaseMax,
    pensionRate: city.pensionRate,
    medicalRate: city.medicalRate,
    unemploymentRate: city.unemploymentRate,
    housingFundRate: city.housingFundRate,
    medicalExtra: city.medicalExtra,
  };
}

/** 取出真正参与计算的累计数据（按月记录模式下由记录累加）。 */
export function resolveYtd(state: SalaryState): YtdTotals {
  // 减除费用口径和在职月数跟数据来源无关，两种模式都要带上
  const deductionMeta = {
    basicDeductionMode: state.ytd.basicDeductionMode,
    employedMonthIndex: state.ytd.employedMonthIndex,
  };

  if (state.ytdMode !== "records") return { ...state.ytd, ...deductionMeta };

  const fromMonths = computeYtdFromMonths(state.months, state.ytd.monthIndex);
  // 记录模式下累计值是精确的，不能让计算器再用「每月金额 × 月数」去补
  return { ...fromMonths, ...deductionMeta, specialDeductionExact: true };
}

/** 把状态转换成计算器输入（自动处理社保 / 公积金基数）。 */
export function toSalaryInput(state: SalaryState): SalaryInput {
  const social: SocialInsuranceConfig = { ...state.social };
  if (state.socialBaseMode === "auto") {
    social.socialBase = clampBase(
      suggestSocialBase(state.incomes),
      state.social.socialBaseMin,
      state.social.socialBaseMax,
    );
  }
  if (state.housingFundBaseMode === "auto") {
    social.housingFundBase = clampBase(
      suggestHousingFundBase(state.incomes),
      state.social.housingFundBaseMin,
      state.social.housingFundBaseMax,
    );
  }
  return {
    incomes: state.incomes,
    deductions: state.deductions,
    social,
    special: state.special,
    ytd: resolveYtd(state),
    annualBonus: state.annualBonus,
    bonusTaxMode: state.bonusTaxMode,
  };
}

export function computeResult(state: SalaryState): SalaryResult {
  return calcSalary(toSalaryInput(state));
}

/** 累计数据一致性提示：拿出来供界面展示。 */
export function getDataHints(state: SalaryState): string[] {
  const hints: string[] = [];
  const socialBase = suggestSocialBase(state.incomes);
  const fundBase = suggestHousingFundBase(state.incomes);

  if (state.socialBaseMode === "auto") {
    if (socialBase < state.social.socialBaseMin) {
      hints.push(`社保自动基数 ${socialBase.toFixed(2)} 元低于下限，已按下限 ${state.social.socialBaseMin} 元缴纳`);
    } else if (socialBase > state.social.socialBaseMax) {
      hints.push(`社保自动基数 ${socialBase.toFixed(2)} 元高于上限，已按上限 ${state.social.socialBaseMax} 元缴纳`);
    }
  }
  if (state.housingFundBaseMode === "auto") {
    if (fundBase < state.social.housingFundBaseMin) {
      hints.push(`公积金自动基数 ${fundBase.toFixed(2)} 元低于下限，已按下限 ${state.social.housingFundBaseMin} 元缴纳`);
    } else if (fundBase > state.social.housingFundBaseMax) {
      hints.push(`公积金自动基数 ${fundBase.toFixed(2)} 元高于上限，已按上限 ${state.social.housingFundBaseMax} 元缴纳`);
    }
  }
  if (state.ytdMode === "records") {
    const missing = findMissingMonths(state.months, state.ytd.monthIndex);
    if (missing.length) {
      hints.push(`第 ${missing.join("、")} 月缺少记录，累计数据会偏小，建议补上`);
    }
    // 只有当前确实申报了专项附加扣除、但某些月份记为 0 时才提示，避免误报
    const declared = sumSpecialDeductions(state.special) > 0;
    if (declared && resolveYtd(state).hasSpecialGap) {
      hints.push("有月份记录的专项附加扣除为 0，如已申报请补填，否则累计扣除会偏小");
    }
  } else if (state.ytd.monthIndex > 1 && state.ytd.taxableIncome === 0 && state.ytd.taxPaid === 0) {
    hints.push("当前不是 1 月，但累计收入与已缴税额均为 0；如非首月入职，请填写累计数据以准确计算");
  }
  return hints;
}
