import { describe, expect, it } from "vitest";
import {
  calcBonusTaxSeparate,
  calcSalary,
  calcSocial,
  clampBase,
  sumSpecialDeductions,
} from "./calculator";
import type { IncomeItem, SalaryInput, SocialInsuranceConfig, SpecialDeductions, YtdTotals } from "./calculator";

const income = (
  label: string,
  amount: number,
  includeInSocialBase = true,
  taxable = true,
  includeInHousingFundBase = includeInSocialBase,
): IncomeItem => ({
  id: label,
  label,
  amount,
  includeInSocialBase,
  includeInHousingFundBase,
  taxable,
});

const social: SocialInsuranceConfig = {
  socialBase: 15000,
  socialBaseMin: 6821,
  socialBaseMax: 35811,
  housingFundBase: 15000,
  housingFundBaseMin: 2420,
  housingFundBaseMax: 35811,
  pensionRate: 0.08,
  medicalRate: 0.02,
  unemploymentRate: 0.005,
  housingFundRate: 0.12,
  medicalExtra: 3,
};

const noSpecial: SpecialDeductions = {
  childrenEducation: 0,
  continuingEducation: 0,
  seriousIllness: 0,
  housingLoanInterest: 0,
  housingRent: 0,
  elderlyCare: 0,
  infantCare: 0,
};

const firstMonth: YtdTotals = {
  monthIndex: 1,
  taxableIncome: 0,
  socialDeduction: 0,
  specialDeduction: 0,
  taxPaid: 0,
};

function input(overrides: Partial<SalaryInput> = {}): SalaryInput {
  return {
    incomes: [income("基本工资", 15000)],
    deductions: [],
    social,
    special: noSpecial,
    ytd: firstMonth,
    annualBonus: 0,
    bonusTaxMode: "separate",
    ...overrides,
  };
}

describe("calcSocial", () => {
  it("按比例计算个人缴纳部分", () => {
    const result = calcSocial(social);
    expect(result.pension).toBe(1200);
    expect(result.medical).toBe(300);
    expect(result.unemployment).toBe(75);
    expect(result.housingFund).toBe(1800);
    expect(result.medicalExtra).toBe(3);
    expect(result.total).toBe(3378);
  });

  it("基数低于下限时按下限缴纳", () => {
    const result = calcSocial({ ...social, socialBase: 1000, housingFundBase: 1000 });
    expect(result.pension).toBe(545.68);
  });

  it("基数高于上限时按上限缴纳", () => {
    const result = calcSocial({ ...social, socialBase: 100000, housingFundBase: 100000 });
    expect(result.pension).toBeCloseTo(2864.88, 2);
  });
});

describe("clampBase", () => {
  it("限制在区间内", () => {
    expect(clampBase(100, 1000, 2000)).toBe(1000);
    expect(clampBase(5000, 1000, 2000)).toBe(2000);
    expect(clampBase(1500, 1000, 2000)).toBe(1500);
  });

  it("上限为 0 表示不封顶", () => {
    expect(clampBase(999999, 0, 0)).toBe(999999);
  });
});

describe("calcSalary 首月", () => {
  it("收入 15000、无专项附加扣除", () => {
    const result = calcSalary(input());
    expect(result.grossIncome).toBe(15000);
    // 应纳税所得额 = 15000 - 5000 - 3378 = 6622
    expect(result.cumulativeTaxable).toBe(6622);
    // 3% 税率
    expect(result.taxThisMonth).toBeCloseTo(198.66, 2);
    expect(result.netPay).toBeCloseTo(15000 - 3378 - 198.66, 2);
  });

  it("非计税收入不计入应纳税所得额，但计入到手", () => {
    const result = calcSalary(
      input({
        incomes: [income("基本工资", 15000), income("差旅报销", 1000, false, false)],
      }),
    );
    expect(result.grossIncome).toBe(16000);
    expect(result.taxableIncome).toBe(15000);
    expect(result.cumulativeTaxable).toBe(6622);
  });

  it("专项附加扣除减少应纳税所得额", () => {
    const result = calcSalary(
      input({ special: { ...noSpecial, housingRent: 1500, childrenEducation: 2000 } }),
    );
    expect(result.specialDeductionTotal).toBe(3500);
    expect(result.cumulativeTaxable).toBe(3122);
    expect(result.taxThisMonth).toBeCloseTo(93.66, 2);
  });

  it("收入不足以覆盖扣除时个税为 0", () => {
    const result = calcSalary(input({ incomes: [income("基本工资", 7000)] }));
    expect(result.cumulativeTaxable).toBe(0);
    expect(result.taxThisMonth).toBe(0);
  });
});

describe("calcSalary 累计预扣预缴", () => {
  it("年中月按累计口径计算，并扣减已预缴", () => {
    const result = calcSalary(
      input({
        ytd: {
          monthIndex: 6,
          taxableIncome: 15000 * 5,
          socialDeduction: 3378 * 5,
          specialDeduction: 0,
          taxPaid: 198.66 * 5,
        },
      }),
    );
    // 累计 = 90000 - 30000 - 20268 = 39732 → 第二档 10%
    expect(result.cumulativeTaxable).toBe(39732);
    expect(result.cumulativeTax).toBeCloseTo(1453.2, 2);
    expect(result.taxThisMonth).toBeCloseTo(1453.2 - 993.3, 2);
  });

  it("累计收入下滑时本月个税不为负", () => {
    const result = calcSalary(
      input({
        incomes: [income("基本工资", 5000)],
        ytd: {
          monthIndex: 3,
          taxableIncome: 60000,
          socialDeduction: 0,
          specialDeduction: 0,
          taxPaid: 100000,
        },
      }),
    );
    expect(result.taxThisMonth).toBeGreaterThanOrEqual(0);
  });

  it("未填累计专项附加扣除时，按每月金额 × 已过月数自动累计", () => {
    // 第 4 月：累计收入 15000 − 减除费用 20000 − 社保 3378 − 专项附加 1500×4 < 0，应纳税所得额为 0
    const withSpecial = calcSalary(
      input({
        special: { ...noSpecial, housingRent: 1500 },
        ytd: { ...firstMonth, monthIndex: 4 },
      }),
    );
    expect(withSpecial.cumulativeTaxable).toBe(0);
    expect(withSpecial.taxThisMonth).toBe(0);

    const withoutSpecial = calcSalary(input({ ytd: { ...firstMonth, monthIndex: 4 } }));
    expect(withoutSpecial.cumulativeTaxable).toBe(0);

    // 高收入场景下能看出自动累计的效果：未填时按 1500 × 4 = 6000 累计
    const incomeItem = [income("基本工资", 40000)];
    const highSocial = { ...social, socialBase: 35811, housingFundBase: 35811 };
    const highIncome = calcSalary(
      input({
        incomes: incomeItem,
        social: highSocial,
        special: { ...noSpecial, housingRent: 1500 },
        ytd: { ...firstMonth, monthIndex: 4 },
      }),
    );
    expect(highIncome.specialDeductionTotal).toBe(1500);
    expect(highIncome.cumulativeTaxable).toBeCloseTo(40000 - 20000 - highIncome.social.total - 6000, 2);

    // 显式填写累计值 3000 时以其为准，再叠加本月 1500（合计 4500），应纳税所得额多 1500
    const explicit = calcSalary(
      input({
        incomes: incomeItem,
        social: highSocial,
        special: { ...noSpecial, housingRent: 1500 },
        ytd: { ...firstMonth, monthIndex: 4, specialDeduction: 3000 },
      }),
    );
    expect(explicit.cumulativeTaxable).toBeCloseTo(highIncome.cumulativeTaxable + 1500, 2);
  });
});

describe("年终奖", () => {
  it("单独计税：36000 元奖金税率为 3%", () => {
    expect(calcBonusTaxSeparate(36000)).toBe(1080);
  });

  it("单独计税：30000 元以内按 3%", () => {
    expect(calcBonusTaxSeparate(30000)).toBe(900);
  });

  it("单独计税：税率跳档", () => {
    // 36000/12 = 3000 → 3% 档；36001/12 > 3000 → 10% 快速扣除 210
    expect(calcBonusTaxSeparate(36001)).toBeCloseTo(3390.1, 2);
  });

  it("并入综合所得时计入累计应纳税所得额", () => {
    const separate = calcSalary(input({ annualBonus: 36000, bonusTaxMode: "separate" }));
    const combined = calcSalary(input({ annualBonus: 36000, bonusTaxMode: "combined" }));
    expect(separate.bonusTax).toBe(1080);
    expect(combined.bonusTax).toBe(0);
    expect(combined.cumulativeTaxable).toBe(6622 + 36000);
    expect(combined.taxThisMonth).toBeGreaterThan(separate.taxThisMonth);
  });
});

describe("sumSpecialDeductions", () => {
  it("汇总所有专项附加扣除", () => {
    expect(
      sumSpecialDeductions({
        childrenEducation: 2000,
        continuingEducation: 400,
        seriousIllness: 0,
        housingLoanInterest: 1000,
        housingRent: 0,
        elderlyCare: 3000,
        infantCare: 2000,
      }),
    ).toBe(8400);
  });
});

describe("自定义扣除项", () => {
  it("税前扣除减少应纳税所得额，税后扣除只影响到手", () => {
    const preTax = calcSalary(
      input({
        deductions: [{ id: "a", label: "企业年金", amount: 500, preTax: true }],
      }),
    );
    const afterTax = calcSalary(
      input({
        deductions: [{ id: "b", label: "扣款", amount: 500, preTax: false }],
      }),
    );
    expect(preTax.cumulativeTaxable).toBe(6622 - 500);
    expect(afterTax.cumulativeTaxable).toBe(6622);
    // 两者到手都扣了 500，但税前扣除少缴 15 元税
    expect(afterTax.netPay).toBeCloseTo(preTax.netPay - 15, 2);
  });
});
