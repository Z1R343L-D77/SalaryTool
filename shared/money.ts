/**
 * 金额与数值工具。
 *
 * 工资、社保、公积金、个税都以「元」为单位、保留两位小数（分）。
 * 所有计算统一走 round2，避免浮点误差在累计过程中被放大。
 *
 * 加班费的小时工资是例外：它是「月薪 ÷ 174」折算出来的中间值，
 * 只留两位会让误差被工时放大（22.32 × 174 = 3883.68，实际 22.325 × 174 = 3884.55），
 * 所以基数另有一套四位小数的版本。
 */

/** 四舍五入到指定小数位。 */
export function roundN(value: number, digits: number): number {
  if (!Number.isFinite(value)) return 0;
  const factor = 10 ** digits;
  return Math.round((value + Number.EPSILON) * factor) / factor;
}

/** 四舍五入到 2 位小数（分）。 */
export function round2(value: number): number {
  return roundN(value, 2);
}

/** 四舍五入到 4 位小数，用于小时工资这类折算出来的中间值。 */
export function round4(value: number): number {
  return roundN(value, 4);
}

/** 限制在 [min, max] 区间内。 */
export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

/** 把任意输入安全地转成数字，非法值返回 fallback。 */
export function toAmount(value: unknown, fallback = 0): number {
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : fallback;
  }
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number.parseFloat(value.replace(/,/g, "").replace(/[^\d.-]/g, ""));
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  return fallback;
}

/** 非负数字，用于所有输入项。 */
export function toNonNegative(value: unknown): number {
  return Math.max(0, toAmount(value));
}

const moneyFormatter = new Intl.NumberFormat("zh-CN", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** 小时工资用：保留四位小数，末尾的 0 去掉（22.3250 → 22.325）。 */
const preciseFormatter = new Intl.NumberFormat("zh-CN", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 4,
});

const integerFormatter = new Intl.NumberFormat("zh-CN", {
  maximumFractionDigits: 0,
});

/** 12345.6 -> "12,345.60" */
export function formatMoney(value: number): string {
  return moneyFormatter.format(round2(value));
}

/**
 * 12345.6789 -> "12,345.6789"
 *
 * 用于小时工资、单价这类折算出来的值。金额本身仍然只到分，
 * 但折算基数要到厘以下才不至于让误差被工时放大。
 */
export function formatPrecise(value: number): string {
  return preciseFormatter.format(round4(value));
}

/** 12345.6 -> "12,346" */
export function formatInteger(value: number): string {
  return integerFormatter.format(Math.round(value));
}

/** 0.0325 -> "3.25%" */
export function formatRate(rate: number, digits = 2): string {
  const percent = round2(rate * 100);
  const text = digits === 0 ? String(Math.round(percent)) : percent.toFixed(digits);
  return `${text.replace(/\.0+$/, "").replace(/(\.\d*[1-9])0+$/, "$1")}%`;
}

/** 百分比数字（12.5）-> "12.5%" */
export function formatPercentNumber(value: number): string {
  return `${round2(value).toString().replace(/\.0+$/, "")}%`;
}

/** 求和。 */
export function sumBy<T>(list: readonly T[], pick: (item: T) => number): number {
  return round2(list.reduce((total, item) => total + toAmount(pick(item)), 0));
}

/** 安全除法，分母为 0 时返回 0。 */
export function safeDivide(numerator: number, denominator: number): number {
  if (!denominator) return 0;
  const result = numerator / denominator;
  return Number.isFinite(result) ? result : 0;
}
