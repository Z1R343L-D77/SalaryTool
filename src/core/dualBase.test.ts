import { describe, expect, it } from "vitest";
import { computeResult, toSalaryInput } from "./defaults";
import type { SalaryState } from "./defaults";
import { normalizeState } from "./storage";
import { computeYtdFromMonths, findMissingMonths } from "./history";
import type { MonthRecord } from "./history";
import mySalary from "../../configs/my-salary.json";

const BASE_SOCIAL = {
  socialBase: 9000,
  socialBaseMin: 7384,
  socialBaseMax: 36921,
  housingFundBase: 8000,
  housingFundBaseMin: 2690,
  housingFundBaseMax: 36921,
  pensionRate: 0.08,
  medicalRate: 0.02,
  unemploymentRate: 0.005,
  housingFundRate: 0.07,
  medicalExtra: 0,
};

const NO_SPECIAL = {
  childrenEducation: 0,
  continuingEducation: 0,
  seriousIllness: 0,
  housingLoanInterest: 0,
  elderlyCare: 0,
  infantCare: 0,
  housingRent: 2000,
};

function makeState(overrides: Partial<SalaryState> = {}): SalaryState {
  return normalizeState({
    cityId: "shanghai",
    socialBaseMode: "manual",
    housingFundBaseMode: "manual",
    incomes: [
      { label: "基本工资", amount: 8000, includeInSocialBase: true, includeInHousingFundBase: true },
      { label: "综合绩效", amount: 1500, includeInSocialBase: true, includeInHousingFundBase: false },
      { label: "加班费", amount: 1200, includeInSocialBase: false, includeInHousingFundBase: false },
    ],
    social: BASE_SOCIAL,
    special: NO_SPECIAL,
    ytd: { monthIndex: 4, taxableIncome: 28500, socialDeduction: 4515, specialDeduction: 6000, taxPaid: 269.55 },
    ...overrides,
  });
}

const record = (month: number, income: number, social = 1505, special = 2000, tax = 0): MonthRecord => ({
  id: `m${month}`,
  month,
  taxableIncome: income,
  socialDeduction: social,
  specialDeduction: special,
  taxPaid: tax,
  note: "",
});

describe("双基数模式", () => {
  it("社保和公积金各自独立推算", () => {
    const state = makeState({ socialBaseMode: "auto", housingFundBaseMode: "auto" });
    const input = toSalaryInput(state);
    // 社保 = 基本 8000 + 绩效 1500 = 9500
    expect(input.social.socialBase).toBe(9500);
    // 公积金 = 只有基本工资 8000
    expect(input.social.housingFundBase).toBe(8000);
  });

  it("一个自动一个手动也能组合", () => {
    const state = makeState({ socialBaseMode: "manual", housingFundBaseMode: "auto" });
    const input = toSalaryInput(state);
    expect(input.social.socialBase).toBe(9000);
    expect(input.social.housingFundBase).toBe(8000);
  });

  it("自动基数受上下限约束", () => {
    const state = makeState({
      socialBaseMode: "auto",
      housingFundBaseMode: "auto",
      incomes: [
        { id: "a", label: "基本工资", amount: 100000, includeInSocialBase: true, includeInHousingFundBase: true, taxable: true },
      ],
    });
    const input = toSalaryInput(state);
    expect(input.social.socialBase).toBe(36921);
    expect(input.social.housingFundBase).toBe(36921);
  });

  it("导入的配置能算出完整结果", () => {
    const result = computeResult(normalizeState(mySalary));
    expect(result.netPay).toBe(12034.98);
    expect(result.taxThisMonth).toBeCloseTo(343.02, 2);
  });
});

describe("按月记录累加", () => {
  it("只累加本月之前的记录", () => {
    const months = [record(1, 9500), record(2, 9500), record(3, 9500), record(4, 10100)];
    const ytd = computeYtdFromMonths(months, 4);
    expect(ytd.taxableIncome).toBe(28500);
    expect(ytd.socialDeduction).toBe(4515);
    expect(ytd.specialDeduction).toBe(6000);
    expect(ytd.monthIndex).toBe(4);
  });

  it("同一个月有多条时取最后一条", () => {
    const months = [record(1, 8000), record(1, 9500)];
    expect(computeYtdFromMonths(months, 2).taxableIncome).toBe(9500);
  });

  it("累计为 0 时不会被自动推算出专项附加扣除", () => {
    const state = makeState({
      ytdMode: "records",
      months: [],
      ytd: { monthIndex: 4, taxableIncome: 0, socialDeduction: 0, specialDeduction: 0, taxPaid: 0 },
    });
    const result = computeResult(state);
    // 手填模式会补 2000 × 3 = 6000 的专项附加，记录模式不该补
    expect(result.specialDeductionTotal).toBe(2000);
    expect(result.cumulativeTaxable).toBe(0);
  });

  it("记录模式下累计专项附加按记录实算，不按每月金额推算", () => {
    // 前三个月未申报租金（special 记 0），本月申报 2,000
    const state = makeState({
      ytdMode: "records",
      months: [
        record(1, 9500, 1505, 0, 89.85),
        record(2, 9500, 1505, 0, 89.85),
        record(3, 9500, 1505, 0, 89.85),
      ],
      ytd: { monthIndex: 4, taxableIncome: 0, socialDeduction: 0, specialDeduction: 0, taxPaid: 0 },
    });
    const result = computeResult(state);
    // 累计收入 28500 + 10700 = 39200
    // − 20000 − 6020 − (0 + 2000) = 11180
    expect(result.cumulativeTaxable).toBe(11180);
    // 累计应纳 335.4，已预缴 269.55
    expect(result.taxThisMonth).toBeCloseTo(65.85, 2);
  });

  it("记录模式下累计扣除为 0 时不会补成推算值", () => {
    const state = makeState({
      ytdMode: "records",
      months: [],
      ytd: { monthIndex: 4, taxableIncome: 0, socialDeduction: 0, specialDeduction: 0, taxPaid: 0 },
    });
    const result = computeResult(state);
    expect(result.specialDeductionTotal).toBe(2000);
    // 只有本月 2000，没有按「2000 × 4」补 8000
    expect(result.cumulativeTaxable).toBe(0);
  });

  it("找出缺失的月份", () => {
    const months = [record(1, 9500), record(3, 9500)];
    expect(findMissingMonths(months, 4)).toEqual([2]);
    // 第 2 月时，只需第 1 月的记录
    expect(findMissingMonths(months, 2)).toEqual([]);
    expect(findMissingMonths(months, 1)).toEqual([]);
  });

  it("记录为空时累计全为 0", () => {
    const ytd = computeYtdFromMonths([], 4);
    expect(ytd).toMatchObject({
      monthIndex: 4,
      taxableIncome: 0,
      socialDeduction: 0,
      specialDeduction: 0,
      taxPaid: 0,
    });
  });
});
