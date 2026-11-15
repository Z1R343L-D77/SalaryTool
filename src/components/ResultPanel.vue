<script setup lang="ts">
import { computed, ref } from "vue";
import type { SalaryResult } from "../core/calculator";
import { formatMoney, formatRate, round2 } from "../core/money";

/**
 * 结果面板：固定右侧，突出「实发到手」，下方是明细流水。
 */
const props = defineProps<{
  result: SalaryResult;
  monthIndex: number;
  hints: string[];
}>();

const showBreakdown = ref(true);

const groups = computed(() => {
  const rows = props.result.rows;
  const income = rows.filter((r) => r.kind === "income");
  const social = rows.filter((r) => r.kind === "social");
  const deduction = rows.filter((r) => r.kind === "deduction");
  const tax = rows.filter((r) => r.kind === "tax");
  return { income, social, deduction, tax };
});

const incomeTotal = computed(() => round2(groups.value.income.reduce((s, r) => s + r.amount, 0)));
const socialTotal = computed(() => round2(groups.value.social.reduce((s, r) => s + r.amount, 0)));
const deductionTotal = computed(() => round2(groups.value.deduction.reduce((s, r) => s + r.amount, 0)));
const taxTotal = computed(() => round2(groups.value.tax.reduce((s, r) => s + r.amount, 0)));

/** 扣除合计占税前收入的比例，用来画一条比例条。 */
const parts = computed(() => {
  const gross = Math.max(incomeTotal.value, 0.01);
  return [
    { key: "net", label: "到手", value: Math.max(props.result.netPay, 0), color: "var(--positive)" },
    { key: "social", label: "社保公积金", value: Math.abs(socialTotal.value), color: "var(--accent)" },
    { key: "tax", label: "个税", value: Math.abs(taxTotal.value), color: "var(--negative)" },
    { key: "other", label: "其他", value: Math.abs(deductionTotal.value), color: "var(--text-muted)" },
  ].map((p) => ({ ...p, percent: (p.value / gross) * 100 }));
});
</script>

<template>
  <aside class="result">
    <div class="result__hero">
      <div class="result__label">本月实发到手</div>
      <div class="result__amount">
        <span class="result__currency">¥</span>
        <span class="num">{{ formatMoney(result.netPay) }}</span>
      </div>
      <div class="result__sub">
        <span>税前 {{ formatMoney(incomeTotal) }}</span>
        <span class="dot">·</span>
        <span>扣除 {{ formatMoney(Math.abs(socialTotal + taxTotal + deductionTotal)) }}</span>
        <span class="dot">·</span>
        <span>第 {{ monthIndex }} 月</span>
      </div>

      <div class="ratio-bar" :title="'到手占比 ' + formatRate(result.netPay / Math.max(incomeTotal, 0.01))">
        <span
          v-for="part in parts"
          :key="part.key"
          class="ratio-bar__seg"
          :style="{ width: part.percent + '%', background: part.color }"
        />
      </div>
      <div class="ratio-legend">
        <span v-for="part in parts" :key="part.key" class="ratio-legend__item">
          <i :style="{ background: part.color }" />{{ part.label }}
          <strong class="num">{{ formatRate(part.percent / 100, 1) }}</strong>
        </span>
      </div>
    </div>

    <div class="result__kpis">
      <div class="kpi">
        <span class="kpi__label">本月个税</span>
        <span class="kpi__value num">{{ formatMoney(result.taxThisMonth) }}</span>
      </div>
      <div class="kpi">
        <span class="kpi__label">累计应纳税所得额</span>
        <span class="kpi__value num">{{ formatMoney(result.cumulativeTaxable) }}</span>
      </div>
      <div class="kpi">
        <span class="kpi__label">累计应纳个税</span>
        <span class="kpi__value num">{{ formatMoney(result.cumulativeTax) }}</span>
      </div>
      <div class="kpi">
        <span class="kpi__label">实际税负率</span>
        <span class="kpi__value num">{{ formatRate(result.effectiveTaxRate, 2) }}</span>
      </div>
    </div>

    <div v-if="result.bonusGross > 0" class="bonus-card">
      <div class="bonus-card__row">
        <span>年终奖</span>
        <span class="num">{{ formatMoney(result.bonusGross) }}</span>
      </div>
      <div class="bonus-card__row bonus-card__row--muted">
        <span>年终奖个税</span>
        <span class="num">{{ formatMoney(result.bonusTax) }}</span>
      </div>
    </div>

    <div v-if="hints.length" class="result__hints">
      <div v-for="hint in hints" :key="hint" class="hint">⚠ {{ hint }}</div>
    </div>

    <div class="result__toggle">
      <button class="btn btn--ghost btn--sm" type="button" @click="showBreakdown = !showBreakdown">
        {{ showBreakdown ? "收起明细" : "展开明细" }}
      </button>
    </div>

    <div v-if="showBreakdown" class="breakdown">
      <div class="breakdown__group">
        <div class="breakdown__head">
          <span>收入</span>
          <span class="num">{{ formatMoney(incomeTotal) }}</span>
        </div>
        <div v-for="row in groups.income" :key="row.key" class="breakdown__row">
          <span class="breakdown__name">
            {{ row.label }}
            <em v-if="row.hint" class="breakdown__hint">{{ row.hint }}</em>
          </span>
          <span class="num">{{ formatMoney(row.amount) }}</span>
        </div>
      </div>

      <div class="breakdown__group">
        <div class="breakdown__head">
          <span>社保 / 公积金</span>
          <span class="num">{{ formatMoney(socialTotal) }}</span>
        </div>
        <div v-for="row in groups.social" :key="row.key" class="breakdown__row">
          <span class="breakdown__name">
            {{ row.label }}
            <em v-if="row.hint" class="breakdown__hint">{{ row.hint }}</em>
          </span>
          <span class="num">{{ formatMoney(row.amount) }}</span>
        </div>
        <div class="breakdown__row breakdown__row--meta">
          <span>缴费基数</span>
          <span class="num">社保 {{ formatMoney(result.socialBaseUsed) }} / 公积金 {{ formatMoney(result.housingFundBaseUsed) }}</span>
        </div>
      </div>

      <div v-if="deductionTotal !== 0" class="breakdown__group">
        <div class="breakdown__head">
          <span>其他扣除</span>
          <span class="num">{{ formatMoney(deductionTotal) }}</span>
        </div>
        <div v-for="row in groups.deduction" :key="row.key" class="breakdown__row">
          <span class="breakdown__name">
            {{ row.label }}
            <em v-if="row.hint" class="breakdown__hint">{{ row.hint }}</em>
          </span>
          <span class="num">{{ formatMoney(row.amount) }}</span>
        </div>
      </div>

      <div class="breakdown__group">
        <div class="breakdown__head">
          <span>个人所得税</span>
          <span class="num">{{ formatMoney(taxTotal) }}</span>
        </div>
        <div v-for="row in groups.tax" :key="row.key" class="breakdown__row">
          <span class="breakdown__name">{{ row.label }}</span>
          <span class="num">{{ formatMoney(row.amount) }}</span>
        </div>
        <div class="breakdown__row breakdown__row--meta">
          <span>专项附加扣除（每月）</span>
          <span class="num">{{ formatMoney(result.specialDeductionTotal) }}</span>
        </div>
      </div>
    </div>

    <footer class="result__foot">数据仅保存在本机 · 计算结果为估算，以实际工资条为准</footer>
  </aside>
</template>

<style scoped>
.result {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 14px;
  background: var(--glass-2);
  backdrop-filter: blur(30px) saturate(180%);
  -webkit-backdrop-filter: blur(30px) saturate(180%);
  border: 1px solid var(--border);
  border-radius: var(--radius-panel);
  box-shadow: var(--specular-top), var(--specular-rim), var(--shadow-panel);
  min-height: 100%;
}

.result__hero {
  padding: 16px;
  border-radius: var(--radius-card);
  /* 主数字区：一层更亮的玻璃，像贴在面板上的一块镜片 */
  background: linear-gradient(
    168deg,
    rgba(255, 255, 255, 0.14) 0%,
    rgba(255, 255, 255, 0.05) 46%,
    rgba(255, 255, 255, 0.02) 100%
  );
  border: 1px solid rgba(255, 255, 255, 0.14);
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.22), 0 10px 28px -18px rgba(0, 0, 0, 0.8);
}

.result__label {
  font-size: 11px;
  color: var(--text-muted);
  letter-spacing: 0.02em;
}

.result__amount {
  display: flex;
  align-items: baseline;
  gap: 4px;
  margin-top: 4px;
  font-family: var(--font-serif);
  font-size: 32px;
  font-weight: 700;
  letter-spacing: -0.01em;
  color: var(--text-strong);
  line-height: 1.15;
  text-shadow: 0 1px 12px rgba(0, 0, 0, 0.35);
}

.result__amount .num {
  font-family: var(--font-serif);
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}

.result__currency {
  font-size: 17px;
  font-weight: 400;
  color: var(--text-muted);
}

.result__sub {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  margin-top: 6px;
  font-size: 12px;
  color: var(--text-muted);
}

.dot {
  opacity: 0.4;
}

.ratio-bar {
  display: flex;
  height: 6px;
  margin-top: 12px;
  border-radius: var(--radius-pill);
  overflow: hidden;
  background: rgba(0, 0, 0, 0.28);
  box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.5);
}

.ratio-bar__seg {
  height: 100%;
  transition: width 200ms ease-out;
}

.ratio-legend {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 12px;
  margin-top: 8px;
  font-size: 11px;
  color: var(--text-muted);
}

.ratio-legend__item {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

.ratio-legend__item i {
  width: 7px;
  height: 7px;
  border-radius: 2px;
}

.ratio-legend__item strong {
  color: var(--text);
  font-weight: 500;
}

.result__kpis {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 1px;
  overflow: hidden;
  border-radius: var(--radius-control);
  border: 1px solid var(--border);
  background: var(--divider);
}

.kpi {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 10px 12px;
  background: rgba(255, 255, 255, 0.035);
}

.kpi__label {
  font-size: 11px;
  letter-spacing: 0.02em;
  color: var(--text-muted);
}

.kpi__value {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-strong);
}

.bonus-card {
  padding: 10px 12px;
  border-radius: var(--radius-control);
  border: 1px solid var(--border);
  background: rgba(255, 255, 255, 0.045);
  font-size: 12px;
}

.bonus-card__row {
  display: flex;
  justify-content: space-between;
  padding: 2px 0;
  color: var(--text-strong);
}

.bonus-card__row--muted {
  color: var(--text-muted);
}

.result__hints {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.result__toggle {
  display: flex;
  justify-content: center;
  border-top: 1px solid var(--divider);
  padding-top: 8px;
}

.breakdown {
  display: flex;
  flex-direction: column;
  gap: 14px;
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding-right: 4px;
}

.breakdown__group {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.breakdown__head {
  display: flex;
  justify-content: space-between;
  padding: 4px 0;
  margin-bottom: 2px;
  border-bottom: 1px solid var(--divider);
  font-size: 12px;
  font-weight: 600;
  color: var(--text-strong);
}

.breakdown__row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  padding: 4px 0;
  font-size: 12px;
  color: var(--text);
}

.breakdown__row--meta {
  color: var(--text-muted);
  font-size: 11px;
}

.breakdown__name {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.breakdown__hint {
  font-size: 10px;
  font-style: normal;
  color: var(--text-faint);
}

.result__foot {
  padding-top: 10px;
  border-top: 1px solid var(--divider);
  font-size: 11px;
  color: var(--text-faint);
  text-align: center;
}
</style>
