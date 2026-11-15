import { computed, reactive, watch, watchEffect } from "vue";
import type { CitySocialPolicy } from "../core/cityPolicies";
import { CITY_POLICIES, findCityPolicy } from "../core/cityPolicies";
import type { SalaryResult } from "../core/calculator";
import { clampBase, suggestHousingFundBase, suggestSocialBase } from "../core/calculator";
import { calcOvertime } from "../core/overtime";
import {
  DEDUCTION_PRESETS,
  INCOME_PRESETS,
  createDefaultState,
  socialConfigFromCity,
  uid,
} from "../core/defaults";
import type { SalaryState } from "../core/defaults";
import { loadState, normalizeState, saveState } from "../core/storage";
import type { DeductionItem, IncomeItem } from "../core/calculator";
import { computeResult, getDataHints } from "../core/defaults";
import { round2 } from "../core/money";

const saved = loadState();
export const state = reactive<SalaryState>(saved ?? createDefaultState());

export const result = computed<SalaryResult>(() => computeResult(state));
export const hints = computed<string[]>(() => getDataHints(state));
export const cities = CITY_POLICIES;

export const selectedCity = computed<CitySocialPolicy>(() => findCityPolicy(state.cityId));

// 防抖写入，避免每次输入都同步写盘
let saveTimer: ReturnType<typeof setTimeout> | undefined;
watch(
  state,
  () => {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => saveState(state), 300);
  },
  { deep: true },
);

// 自动模式下把推算出来的基数写回 state，便于展示与持久化
watchEffect(() => {
  if (state.socialBaseMode === "auto") {
    const socialBase = clampBase(
      suggestSocialBase(state.incomes),
      state.social.socialBaseMin,
      state.social.socialBaseMax,
    );
    if (state.social.socialBase !== socialBase) state.social.socialBase = socialBase;
  }
  if (state.housingFundBaseMode === "auto") {
    const fundBase = clampBase(
      suggestHousingFundBase(state.incomes),
      state.social.housingFundBaseMin,
      state.social.housingFundBaseMax,
    );
    if (state.social.housingFundBase !== fundBase) state.social.housingFundBase = fundBase;
  }
});

// —— 加班费 ↔ 收入项联动 ——

/**
 * 加班费要写入的收入项；没绑定或绑定项被删掉时返回 undefined。
 *
 * 注意：只认「加班费」，不能用「加班」模糊匹配 ——
 * 加班费是按工时×倍率算出来的，加班补贴 / 加班补助是公司另发的一笔固定钱，
 * 两者是两条独立的收入项，混在一起会算错。
 */
export function findOvertimeIncome(): IncomeItem | undefined {
  const id = state.overtimeSync.incomeId;
  if (id) return state.incomes.find((item) => item.id === id);
  return state.incomes.find((item) => item.label.trim() === "加班费");
}

/**
 * 打开联动时确保有一个可写入的「加班费」收入项：
 * 先按 id 找，找不到就按名字找，都没有就新建一项。
 */
export function ensureOvertimeIncome(): IncomeItem {
  const existing = findOvertimeIncome();
  if (existing) {
    state.overtimeSync.incomeId = existing.id;
    return existing;
  }
  const id = uid("income");
  const item: IncomeItem = {
    id,
    label: "加班费",
    amount: 0,
    // 加班费一般不并进社保 / 公积金基数，但要计税
    includeInSocialBase: false,
    includeInHousingFundBase: false,
    taxable: true,
  };
  state.incomes.push(item);
  state.overtimeSync.incomeId = id;
  return item;
}

export function setOvertimeSyncEnabled(enabled: boolean): void {
  state.overtimeSync.enabled = enabled;
  if (enabled) {
    ensureOvertimeIncome();
  } else {
    // 关闭联动时把金额清零，避免留下一个和工时对不上的陈旧数字
    const target = findOvertimeIncome();
    if (target) target.amount = 0;
  }
}

/** 把当前加班费合计写进目标收入项。 */
export function pushOvertimeToIncome(): void {
  const target = findOvertimeIncome();
  if (!target) return;
  const total = round2(calcOvertime(state.overtime).totalPay);
  if (target.amount !== total) target.amount = total;
}

// 联动打开时，工时或基数一变就同步金额
watchEffect(() => {
  if (!state.overtimeSync.enabled) return;
  const target = state.overtimeSync.incomeId
    ? state.incomes.find((item) => item.id === state.overtimeSync.incomeId)
    : undefined;
  // 绑定项被删掉了，就重新挂一个
  if (!target) {
    ensureOvertimeIncome();
    return;
  }
  const total = round2(calcOvertime(state.overtime).totalPay);
  if (target.amount !== total) target.amount = total;
});

// —— 动作 ——

export function applyCity(cityId: string): void {
  state.cityId = cityId;
  const city = findCityPolicy(cityId);
  // 手动填的基数保留，自动模式的基数由 watchEffect 重新推算
  const keepSocial = state.socialBaseMode === "manual" ? state.social.socialBase : undefined;
  const keepFund = state.housingFundBaseMode === "manual" ? state.social.housingFundBase : undefined;
  state.social = socialConfigFromCity(city, keepSocial, keepFund);
}

export function addIncome(presetIndex?: number): void {
  const preset = INCOME_PRESETS[presetIndex ?? 0] ?? INCOME_PRESETS[0];
  state.incomes.push({
    id: uid("income"),
    label: preset.label,
    amount: 0,
    includeInSocialBase: preset.includeInSocialBase,
    includeInHousingFundBase: preset.includeInHousingFundBase,
    taxable: preset.taxable,
  } satisfies IncomeItem);
}

export function removeIncome(id: string): void {
  const index = state.incomes.findIndex((item) => item.id === id);
  if (index >= 0) state.incomes.splice(index, 1);
}

export function addDeduction(presetIndex?: number): void {
  const preset = DEDUCTION_PRESETS[presetIndex ?? 0] ?? DEDUCTION_PRESETS[0];
  state.deductions.push({
    id: uid("deduction"),
    label: preset.label,
    amount: 0,
    preTax: preset.preTax,
  } satisfies DeductionItem);
}

export function removeDeduction(id: string): void {
  const index = state.deductions.findIndex((item) => item.id === id);
  if (index >= 0) state.deductions.splice(index, 1);
}

// —— 按月记录 ——

export function addMonth(month?: number): void {
  const used = new Set(state.months.map((record) => record.month));
  const target = month ?? (() => {
    for (let m = 1; m <= 12; m += 1) if (!used.has(m)) return m;
    return state.ytd.monthIndex;
  })();
  state.months.push({
    id: uid("month"),
    month: Math.min(12, Math.max(1, target)),
    taxableIncome: 0,
    socialDeduction: 0,
    specialDeduction: 0,
    taxPaid: 0,
    note: "",
  });
  state.months.sort((a, b) => a.month - b.month);
  // 首次添加记录时自动切到记录模式
  if (state.months.length > 0) state.ytdMode = "records";
}

export function removeMonth(id: string): void {
  const index = state.months.findIndex((record) => record.id === id);
  if (index >= 0) state.months.splice(index, 1);
}

export function resetAll(): void {
  applyState(createDefaultState());
}

/** 把一份完整的配置写进当前状态（保持同一个 reactive 对象，界面自动刷新）。 */
export function applyState(next: SalaryState): void {
  state.cityId = next.cityId;
  state.socialBaseMode = next.socialBaseMode;
  state.housingFundBaseMode = next.housingFundBaseMode;
  state.incomes.splice(0, state.incomes.length, ...next.incomes);
  state.deductions.splice(0, state.deductions.length, ...next.deductions);
  Object.assign(state.social, next.social);
  Object.assign(state.special, next.special);
  state.ytdMode = next.ytdMode;
  Object.assign(state.ytd, next.ytd);
  state.months.splice(0, state.months.length, ...next.months);
  state.annualBonus = next.annualBonus;
  state.bonusTaxMode = next.bonusTaxMode;
  Object.assign(state.overtime, next.overtime);
  Object.assign(state.overtimeSync, next.overtimeSync);
}

/**
 * 导入配置：接受 JSON 字符串或已解析的对象。
 * 数据结构不符时抛错，由界面提示用户。
 */
export function importState(input: string | unknown): void {
  let parsed: unknown = input;
  if (typeof input === "string") {
    const text = input.trim();
    if (!text) throw new Error("配置内容为空");
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new Error("不是合法的 JSON，请检查是否漏了括号或引号");
    }
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("配置格式不对，应该是一个 JSON 对象");
  }
  applyState(normalizeState(parsed));
}

export { INCOME_PRESETS, DEDUCTION_PRESETS };
