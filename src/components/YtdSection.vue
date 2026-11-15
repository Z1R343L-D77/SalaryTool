<script setup lang="ts">
import { computed } from "vue";
import type { SalaryState } from "../core/defaults";
import { resolveYtd } from "../core/defaults";
import { resolveDeductionMonths, sumSpecialDeductions } from "../core/calculator";
import type { MonthRecord } from "../core/history";
import { computeYtdFromMonths, findMissingMonths } from "../core/history";
import { formatMoney, round2 } from "../core/money";
import { addMonth, removeMonth, result } from "../store/useSalaryState";
import NumberField from "./NumberField.vue";

/**
 * 累计数据与年终奖。
 *
 * 两种模式：
 * - 手填：直接填累计收入 / 社保 / 专项附加 / 已缴税额
 * - 按月记录：逐月记录实际工资条数字，累计值自动加出来
 *
 * 「本次计算第 N 月」指的是**当年第几个月**，不是入职第几个月。
 * 年中首次取得工资薪金的人，减除费用可以从当年 1 月起算（5000 × N），
 * 这就是为什么应届生入职当年常常一分税都不用交。
 */
const props = defineProps<{ state: SalaryState }>();

const MONTHS = Array.from({ length: 12 }, (_, i) => i + 1);

const effectiveYtd = computed(() => resolveYtd(props.state));
const missingMonths = computed(() =>
  props.state.ytdMode === "records" ? findMissingMonths(props.state.months, props.state.ytd.monthIndex) : [],
);

/** 实际用于累计减除费用的月数 */
const deductionMonths = computed(() => resolveDeductionMonths(effectiveYtd.value));

/** 是否按「在本单位第几个月」口径 */
const isEmployedMode = computed(() => props.state.ytd.basicDeductionMode === "employedMonth");

/** 在本单位月数：默认等于当年月份（首次就业），可手动改小 */
const employedMonthIndex = computed({
  get: () => props.state.ytd.employedMonthIndex ?? props.state.ytd.monthIndex,
  set: (value: number) => {
    const n = Math.min(props.state.ytd.monthIndex, Math.max(1, Math.round(value) || 1));
    props.state.ytd.employedMonthIndex = n;
  },
});

function setDeductionMode(mode: "calendarMonth" | "employedMonth"): void {
  props.state.ytd.basicDeductionMode = mode;
  if (mode === "employedMonth" && !props.state.ytd.employedMonthIndex) {
    props.state.ytd.employedMonthIndex = props.state.ytd.monthIndex;
  }
}

const rows = computed(() =>
  [...props.state.months].sort((a, b) => a.month - b.month),
);

const ytdIncomePerMonth = computed(() => {
  const monthsElapsed = Math.max(0, props.state.ytd.monthIndex - 1);
  if (monthsElapsed === 0) return 0;
  return effectiveYtd.value.taxableIncome / monthsElapsed;
});

/** 记录模式下「本月这一列」的推荐值：直接用当前计算结果。 */
function useCurrentResult(record: MonthRecord): void {
  const r = result.value;
  record.taxableIncome = round2(r.taxableIncome);
  record.specialDeduction = round2(sumSpecialDeductions(props.state.special));
  record.socialDeduction = round2(r.social.total);
  record.taxPaid = round2(r.taxThisMonth);
}

/** 记录模式下累计行的汇总预览。 */
const previewSum = computed(() => computeYtdFromMonths(props.state.months, props.state.ytd.monthIndex));
</script>

<template>
  <section class="card">
    <header class="card__header">
      <h2 class="card__title">
        累计数据与年终奖
        <span class="card__subtitle">累计预扣预缴需要本年度已累计的金额</span>
      </h2>
      <div class="month-picker">
        <span class="month-picker__label">当年第</span>
        <select v-model.number="state.ytd.monthIndex" class="select" aria-label="当年第几个月">
          <option v-for="month in MONTHS" :key="month" :value="month">{{ month }}</option>
        </select>
        <span class="month-picker__label">月</span>
      </div>
    </header>

    <div class="card__body">
      <!-- 减除费用口径：决定 5000 元/月要乘几个 -->
      <div class="deduction-block">
        <div class="deduction-block__head">
          <span class="deduction-block__title">基本减除费用口径</span>
          <div class="segmented segmented--sm" role="radiogroup" aria-label="减除费用口径">
            <button
              type="button"
              :class="{ active: !isEmployedMode }"
              @click="setDeductionMode('calendarMonth')"
            >
              当年月份数
            </button>
            <button
              type="button"
              :class="{ active: isEmployedMode }"
              @click="setDeductionMode('employedMonth')"
            >
              本单位月数
            </button>
          </div>
        </div>

        <div class="deduction-block__row">
          <span class="deduction-block__calc">
            5,000 × <strong class="num">{{ deductionMonths }}</strong> 个月 =
            <strong class="num">{{ formatMoney(deductionMonths * 5000) }}</strong> 元
          </span>
          <label v-if="isEmployedMode" class="deduction-block__input">
            <span>在本单位第</span>
            <select v-model.number="employedMonthIndex" class="select select--employed">
              <option v-for="month in MONTHS" :key="month" :value="month" :disabled="month > state.ytd.monthIndex">
                {{ month }}
              </option>
            </select>
            <span>个月</span>
          </label>
        </div>

        <p class="deduction-block__hint">
          <template v-if="!isEmployedMode">
            当年首次取得工资薪金可用这个口径：即使 10 月才入职，减除费用也按 1 月起累计，
            这通常就是应届生入职当年不缴个税的原因。
          </template>
          <template v-else>
            年内已在本单位以外取得过工资收入（例如换工作）时用这个口径，避免重复享受减除费用。
          </template>
        </p>
      </div>

      <div class="segmented" role="radiogroup" aria-label="累计数据来源">
        <button
          type="button"
          :class="{ active: state.ytdMode === 'manual' }"
          @click="state.ytdMode = 'manual'"
        >
          手填累计
        </button>
        <button
          type="button"
          :class="{ active: state.ytdMode === 'records' }"
          @click="state.ytdMode = 'records'"
        >
          按月记录
        </button>
      </div>

      <!-- —— 手填模式 —— -->
      <template v-if="state.ytdMode === 'manual'">
        <div class="grid">
          <label class="field">
            <span class="field__label">截至上月累计收入</span>
            <NumberField v-model="state.ytd.taxableIncome" placeholder="0.00" />
            <span class="field__hint">
              计税口径；当前折算约 {{ formatMoney(ytdIncomePerMonth) }}/月
            </span>
          </label>
          <label class="field">
            <span class="field__label">截至上月累计社保公积金</span>
            <NumberField v-model="state.ytd.socialDeduction" placeholder="0.00" />
            <span class="field__hint">个人缴纳部分累计</span>
          </label>
          <label class="field">
            <span class="field__label">截至上月累计专项附加扣除</span>
            <NumberField v-model="state.ytd.specialDeduction" placeholder="0.00" />
            <span class="field__hint">不填则按每月金额 × 月数自动累计</span>
          </label>
          <label class="field">
            <span class="field__label">截至上月累计已预缴税额</span>
            <NumberField v-model="state.ytd.taxPaid" placeholder="0.00" />
            <span class="field__hint">工资条「本年累计已缴个税」</span>
          </label>
        </div>
      </template>

      <!-- —— 按月记录模式 —— -->
      <template v-else>
        <p class="records-hint">
          逐月记录工资条上的实际数字，累计值自动加出来。只统计第
          {{ state.ytd.monthIndex }} 月之前的记录。
        </p>

        <div class="table-wrap">
          <table class="records">
            <thead>
              <tr>
                <th class="col-month">月</th>
                <th>计税收入</th>
                <th>社保公积金</th>
                <th>专项附加</th>
                <th>已扣个税</th>
                <th class="col-actions"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="rows.length === 0">
                <td colspan="6" class="empty">还没有记录，点下面的「+ 添加月份」开始。</td>
              </tr>
              <tr v-for="record in rows" :key="record.id" :class="{ 'is-current': record.month >= state.ytd.monthIndex }">
                <td class="col-month">
                  <select v-model.number="record.month" class="select select--xs">
                    <option v-for="month in MONTHS" :key="month" :value="month">{{ month }}</option>
                  </select>
                </td>
                <td><NumberField v-model="record.taxableIncome" /></td>
                <td><NumberField v-model="record.socialDeduction" /></td>
                <td><NumberField v-model="record.specialDeduction" /></td>
                <td><NumberField v-model="record.taxPaid" /></td>
                <td class="col-actions">
                  <button
                    class="btn btn--ghost btn--icon btn--sm"
                    type="button"
                    title="用当前计算结果填入这一行"
                    @click="useCurrentResult(record)"
                  >
                    ⟳
                  </button>
                  <button
                    class="btn btn--ghost btn--icon btn--sm btn--danger"
                    type="button"
                    title="删除"
                    @click="removeMonth(record.id)"
                  >
                    ✕
                  </button>
                </td>
              </tr>
            </tbody>
            <tfoot v-if="rows.length > 0">
              <tr>
                <td class="col-month">合计</td>
                <td class="num">{{ formatMoney(previewSum.taxableIncome) }}</td>
                <td class="num">{{ formatMoney(previewSum.socialDeduction) }}</td>
                <td class="num">{{ formatMoney(previewSum.specialDeduction) }}</td>
                <td class="num">{{ formatMoney(previewSum.taxPaid) }}</td>
                <td class="col-actions"></td>
              </tr>
            </tfoot>
          </table>
        </div>

        <div class="records-actions">
          <button class="btn btn--sm" type="button" @click="addMonth()">+ 添加月份</button>
          <span class="records-actions__sum">
            截至上月累计：
            <strong class="num">{{ formatMoney(previewSum.taxableIncome) }}</strong> 收入 ·
            <strong class="num">{{ formatMoney(previewSum.socialDeduction) }}</strong> 社保公积金 ·
            <strong class="num">{{ formatMoney(previewSum.specialDeduction) }}</strong> 专项附加 ·
            <strong class="num">{{ formatMoney(previewSum.taxPaid) }}</strong> 已缴税
          </span>
        </div>

        <p v-if="missingMonths.length" class="records-warn">
          第 {{ missingMonths.join("、") }} 月缺少记录，累计数据会偏小。
        </p>
      </template>

      <div class="bonus">
        <div class="bonus__head">
          <span class="field__label">年终奖（仅在发放当月填写）</span>
          <div class="segmented segmented--sm">
            <button
              type="button"
              :class="{ active: state.bonusTaxMode === 'separate' }"
              @click="state.bonusTaxMode = 'separate'"
            >
              单独计税
            </button>
            <button
              type="button"
              :class="{ active: state.bonusTaxMode === 'combined' }"
              @click="state.bonusTaxMode = 'combined'"
            >
              并入综合所得
            </button>
          </div>
        </div>
        <NumberField v-model="state.annualBonus" placeholder="0.00" class="bonus__field" />
      </div>

      <p class="tip">
        全年一次性奖金单独计税政策目前延续至 2027 年底，每年只能用一次。
      </p>
    </div>
  </section>
</template>

<style scoped>
.month-picker {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

.month-picker .select {
  height: 30px;
  min-width: 68px;
  font-size: var(--fs-label);
}

/* 顶部「手填 / 按月记录」这组与下方内容之间留出间距；
   分段控件本体样式在 global.css 里，不再重复定义 */
.card__body > .segmented {
  margin-bottom: 14px;
}

/* —— 减除费用口径 —— */

.deduction-block {
  padding: 12px 14px;
  margin-bottom: 14px;
  border-radius: var(--radius-control);
  border: 1px solid var(--border);
  background: var(--glass-1);
}

.deduction-block__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}

.deduction-block__title {
  font-size: var(--fs-label);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-label);
  color: var(--text-strong);
}

.deduction-block__row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  margin-top: 10px;
}

.deduction-block__calc {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

.deduction-block__calc strong {
  color: var(--text-strong);
  font-size: var(--fs-body);
  font-weight: var(--fw-semibold);
}

.deduction-block__input {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

.select--employed {
  height: 28px;
  min-width: 64px;
  font-size: var(--fs-label);
}

.deduction-block__hint {
  margin: 10px 0 0;
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
  color: var(--text-muted);
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
  gap: 14px 16px;
}

.field {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}

.field__label {
  font-size: var(--fs-label);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-label);
  color: var(--text);
}

.field__hint {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.records-hint {
  margin: 0 0 12px;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
  line-height: var(--lh-body);
}

.table-wrap {
  overflow-x: auto;
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
}

.records {
  width: 100%;
  min-width: 620px;
  border-collapse: collapse;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
}

.records th {
  padding: 9px 10px;
  background: var(--glass-2);
  color: var(--text-muted);
  font-weight: var(--fw-medium);
  text-align: left;
  white-space: nowrap;
  border-bottom: 1px solid var(--border);
}

.records td {
  padding: 6px 8px;
  border-bottom: 1px solid var(--border);
  vertical-align: middle;
}

.records tbody tr:last-child td {
  border-bottom: 0;
}

.records tbody tr.is-current td {
  background: var(--glass-2);
  color: var(--text-muted);
}

.records tfoot td {
  padding: 9px 10px;
  background: var(--glass-2);
  font-weight: var(--fw-semibold);
  color: var(--text-strong);
  border-top: 1px solid var(--border);
  white-space: nowrap;
}

.col-month {
  width: 76px;
}

.col-actions {
  width: 68px;
  text-align: right;
  white-space: nowrap;
}

.select--xs {
  height: 30px;
  width: 62px;
  padding: 0 22px 0 8px;
  font-size: var(--fs-label);
}

.empty {
  padding: 18px;
  text-align: center;
  color: var(--text-muted);
}

.records-actions {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px 12px;
  margin-top: 10px;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

.records-actions__sum strong {
  color: var(--text-strong);
  font-weight: var(--fw-semibold);
}

.records-warn {
  margin: 10px 0 0;
  padding: 8px 10px;
  border-radius: var(--radius-sm);
  background: var(--warning-soft);
  color: var(--warning);
  font-size: var(--fs-caption);
  line-height: var(--lh-body);
}

.bonus {
  margin-top: 18px;
  padding-top: 16px;
  border-top: 1px solid var(--divider);
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.bonus__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 8px;
}

.bonus__field {
  max-width: 200px;
}

.tip {
  margin: 16px 0 0;
  padding-top: 12px;
  border-top: 1px solid var(--divider);
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
  color: var(--text-muted);
}
</style>
