import { describe, expect, it } from "vitest";
import { calcSalary, resolveDeductionMonths } from "./calculator";
import type { SalaryInput, SocialInsuranceConfig, SpecialDeductions, YtdTotals } from "./calculator";

/**
 * 减除费用口径（国家税务总局 2020 年第 13 号公告）。
 *
 * 年中首次取得工资薪金的人，减除费用从当年 1 月起算，
 * 这是应届生入职当年常常不缴个税的原因。
 */

const social: SocialInsuranceConfig = {
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

const special: SpecialDeductions = {
  childrenEducation: 0,
  continuingEducation: 0,
  seriousIllness: 0,
  housingLoanInterest: 0,
  housingRent: 2000,
  elderlyCare: 0,
  infantCare: 0,
};

/** 7 月入职、10 月发薪：当年第 10 月，在本单位第 4 个月。 */
function makeInput(overrides: Partial<YtdTotals> = {}): SalaryInput {
  return {
    incomes: [
      {
        id: "i1",
        label: "基本工资",
        amount: 9500,
        includeInSocialBase: true,
        includeInHousingFundBase: true,
        taxable: true,
      },
      {
        id: "i2",
        label: "加班费",
        amount: 1200,
        includeInSocialBase: false,
        includeInHousingFundBase: false,
        taxable: true,
      },
    ],
    deductions: [],
    social,
    special,
    ytd: {
      monthIndex: 10,
      taxableIncome: 28500,
      socialDeduction: 4515,
      specialDeduction: 6000,
      taxPaid: 0,
      ...overrides,
    },
    annualBonus: 0,
    bonusTaxMode: "separate",
  };
}

describe("resolveDeductionMonths", () => {
  it("默认按当年月份数", () => {
    expect(resolveDeductionMonths({ monthIndex: 10, taxableIncome: 0, socialDeduction: 0, specialDeduction: 0, taxPaid: 0 })).toBe(10);
  });

  it("显式 calendarMonth 也是当年月份数", () => {
    expect(
      resolveDeductionMonths({
        monthIndex: 10,
        taxableIncome: 0,
        socialDeduction: 0,
        specialDeduction: 0,
        taxPaid: 0,
        basicDeductionMode: "calendarMonth",
      }),
    ).toBe(10);
  });

  it("employedMonth 口径用本单位月数", () => {
    expect(
      resolveDeductionMonths({
        monthIndex: 10,
        taxableIncome: 0,
        socialDeduction: 0,
        specialDeduction: 0,
        taxPaid: 0,
        basicDeductionMode: "employedMonth",
        employedMonthIndex: 4,
      }),
    ).toBe(4);
  });

  it("本单位月数不能超过当年月份数", () => {
    expect(
      resolveDeductionMonths({
        monthIndex: 4,
        taxableIncome: 0,
        socialDeduction: 0,
        specialDeduction: 0,
        taxPaid: 0,
        basicDeductionMode: "employedMonth",
        employedMonthIndex: 10,
      }),
    ).toBe(4);
  });

  it("employedMonth 模式下没填月数时退回当年月份数", () => {
    expect(
      resolveDeductionMonths({
        monthIndex: 10,
        taxableIncome: 0,
        socialDeduction: 0,
        specialDeduction: 0,
        taxPaid: 0,
        basicDeductionMode: "employedMonth",
      }),
    ).toBe(10);
  });

  it("月份数被夹在 1-12", () => {
    expect(resolveDeductionMonths({ monthIndex: 0, taxableIncome: 0, socialDeduction: 0, specialDeduction: 0, taxPaid: 0 })).toBe(1);
    expect(resolveDeductionMonths({ monthIndex: 13, taxableIncome: 0, socialDeduction: 0, specialDeduction: 0, taxPaid: 0 })).toBe(12);
  });
});

describe("应届生入职当年不缴个税", () => {
  it("7 月入职、10 月发薪：减除费用按 1 月起算，应纳税所得额为 0", () => {
    const result = calcSalary(makeInput());
    // 累计收入 39200 − 5000×10 − 6020 − 8000 < 0
    expect(result.cumulativeTaxable).toBe(0);
    expect(result.cumulativeTax).toBe(0);
    expect(result.taxThisMonth).toBe(0);
    // 到手 = 应付 10700 − 社保公积金 1505
    expect(result.netPay).toBeCloseTo(9195, 2);
  });

  it("如果错按「本单位第 4 个月」算，就会凭空多出一笔税", () => {
    const result = calcSalary(
      makeInput({
        basicDeductionMode: "employedMonth",
        employedMonthIndex: 4,
      }),
    );
    // 39200 − 20000 − 6020 − 8000 = 5180 → 3% 税 155.4
    expect(result.cumulativeTaxable).toBe(5180);
    expect(result.taxThisMonth).toBeCloseTo(155.4, 2);
  });

  it("两种口径的差额是少扣的减除费用（应纳税所得额为 0 时被截断）", () => {
    const calendar = calcSalary(makeInput());
    const employed = calcSalary(makeInput({ basicDeductionMode: "employedMonth", employedMonthIndex: 4 }));
    // 少扣 6 个月 = 30000，但当年口径下应纳税所得额已经是 0，差额被截到 5180
    expect(calendar.cumulativeTaxable).toBe(0);
    expect(employed.cumulativeTaxable - calendar.cumulativeTaxable).toBe(5180);
  });

  it("收入够高时两种口径的差额才等于完整的减除费用差", () => {
    const base: SalaryInput = {
      ...makeInput(),
      incomes: [
        {
          id: "h1",
          label: "基本工资",
          amount: 40000,
          includeInSocialBase: true,
          includeInHousingFundBase: true,
          taxable: true,
        },
      ],
      ytd: {
        monthIndex: 10,
        taxableIncome: 360000,
        socialDeduction: 35921.4,
        specialDeduction: 6000,
        taxPaid: 0,
      },
    };
    const calendar = calcSalary(base);
    const employed = calcSalary({
      ...base,
      ytd: { ...base.ytd, basicDeductionMode: "employedMonth", employedMonthIndex: 4 },
    });
    expect(calendar.cumulativeTaxable).toBeGreaterThan(0);
    // 两者都未触底，差额正好是 6 个月的减除费用
    expect(employed.cumulativeTaxable - calendar.cumulativeTaxable).toBe(30000);
    expect(employed.taxThisMonth).toBeGreaterThan(calendar.taxThisMonth);
  });

  it("全年都按当年月份数时，下半年收入的税也不会凭空出现", () => {
    // 12 月：累计收入 45500，减除 5000×12 = 60000，仍为负
    const result = calcSalary(makeInput({ monthIndex: 12, taxableIncome: 34800, taxPaid: 0 }));
    expect(result.cumulativeTaxable).toBe(0);
    expect(result.taxThisMonth).toBe(0);
  });
});
