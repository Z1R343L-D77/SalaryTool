import { describe, expect, it } from "vitest";
import { computeResult } from "./defaults";
import { normalizeState, exportState } from "./storage";
import mySalary from "../fixtures/my-salary.json";

describe("导入配置", () => {
  it("缺失字段会用默认值补齐，不崩溃", () => {
    const normalized = normalizeState({});
    expect(normalized.cityId).toBeTruthy();
    expect(normalized.incomes.length).toBeGreaterThan(0);
    expect(normalized.social.pensionRate).toBeGreaterThan(0);
  });

  it("非对象输入回落到默认状态", () => {
    expect(normalizeState(null).cityId).toBeTruthy();
    expect(normalizeState("not json").cityId).toBeTruthy();
    expect(normalizeState([]).cityId).toBeTruthy();
  });

  it("数字字符串会被解析成数字", () => {
    const normalized = normalizeState({
      incomes: [{ label: "基本工资", amount: "12,345" }],
      social: { socialBase: "11000", pensionRate: "0.08" },
    });
    expect(normalized.incomes[0].amount).toBe(12345);
    expect(normalized.social.socialBase).toBe(11000);
    expect(normalized.social.pensionRate).toBe(0.08);
  });

  it("未写基数的收入项默认计税，非法金额归零", () => {
    const normalized = normalizeState({
      incomes: [{ label: "餐补", amount: -100 }],
    });
    expect(normalized.incomes[0].taxable).toBe(true);
    expect(normalized.incomes[0].amount).toBe(0);
  });

  it("未知城市回落到自定义档", () => {
    expect(normalizeState({ cityId: "atlantis" }).cityId).toBe("custom");
  });

  it("显式给出基数时自动切到手动模式", () => {
    const normalized = normalizeState({ social: { socialBase: 11000, housingFundBase: 9000 } });
    expect(normalized.socialBaseMode).toBe("manual");
  });

  it("导出再导入保持数值一致", () => {
    const first = normalizeState(mySalary);
    const second = normalizeState(JSON.parse(exportState(first)));
    expect(second).toEqual(first);
  });

  it("示例配置能算出自洽的数", () => {
    const result = computeResult(normalizeState(mySalary));

    // 收入：12000 + 2400 + 330 + 400 + 200
    expect(result.grossIncome).toBe(15330);
    // 社保 14400 × 10.5% = 1512，公积金 12000 × 12% = 1440
    expect(result.social.pension).toBe(1152);
    expect(result.social.medical).toBe(288);
    expect(result.social.unemployment).toBe(72);
    expect(result.social.housingFund).toBe(1440);
    expect(result.social.total).toBe(2952);
    // 按月记录累加：107310 收入 / 20664 社保 / 17000 专项附加 / 1039.38 已缴
    // 122640 − 40000 − 23616 − 20000 = 39024
    expect(result.cumulativeTaxable).toBe(39024);
    // 累计应纳 1382.4，已预缴 1039.38 → 本月 343.02
    expect(result.cumulativeTax).toBeCloseTo(1382.4, 2);
    expect(result.taxThisMonth).toBeCloseTo(343.02, 2);
    // 到手 = 15330 − 2952 − 343.02
    expect(result.netPay).toBe(12034.98);
  });
});
