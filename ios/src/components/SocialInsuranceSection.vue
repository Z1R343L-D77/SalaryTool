<script setup lang="ts">
import { computed } from "vue";
import type { SalaryState } from "@shared/defaults";
import { clampBase, suggestHousingFundBase, suggestSocialBase } from "@shared/calculator";
import { formatMoney, round2 } from "@shared/money";
import { cities } from "../store/useSalaryState";
import NumberField from "./NumberField.vue";

/**
 * 社保公积金设置：城市预设 + 两套基数模式（社保 / 公积金各自自动或手动）+ 比例覆盖。
 *
 * 社保和公积金基数分开，是因为不少公司申报口径不同：
 * 社保按上年度月平均工资，公积金只按基本工资。
 */
const props = defineProps<{ state: SalaryState }>();

const emit = defineEmits<{ "apply-city": [cityId: string] }>();

const suggestedSocial = computed(() => suggestSocialBase(props.state.incomes));
const suggestedFund = computed(() => suggestHousingFundBase(props.state.incomes));

const socialBaseUsed = computed(() =>
  clampBase(
    props.state.socialBaseMode === "auto" ? suggestedSocial.value : props.state.social.socialBase,
    props.state.social.socialBaseMin,
    props.state.social.socialBaseMax,
  ),
);
const fundBaseUsed = computed(() =>
  clampBase(
    props.state.housingFundBaseMode === "auto" ? suggestedFund.value : props.state.social.housingFundBase,
    props.state.social.housingFundBaseMin,
    props.state.social.housingFundBaseMax,
  ),
);

const socialTotal = computed(() =>
  round2(
    socialBaseUsed.value *
      (props.state.social.pensionRate +
        props.state.social.medicalRate +
        props.state.social.unemploymentRate) +
      props.state.social.medicalExtra,
  ),
);
const fundTotal = computed(() =>
  round2(fundBaseUsed.value * props.state.social.housingFundRate),
);
const previewTotal = computed(() => round2(socialTotal.value + fundTotal.value));

/** 两个基数不一致时提示一下，避免用户以为是笔误。 */
const basesDiffer = computed(
  () => Math.abs(socialBaseUsed.value - fundBaseUsed.value) > 0.005,
);
</script>

<template>
  <section class="card">
    <header class="card__header">
      <h2 class="card__title">
        社保 / 公积金
        <span class="card__subtitle">个人缴纳部分</span>
      </h2>
      <select
        class="select"
        :value="state.cityId"
        aria-label="选择城市"
        @change="emit('apply-city', ($event.target as HTMLSelectElement).value)"
      >
        <option v-for="city in cities" :key="city.id" :value="city.id">{{ city.name }}</option>
      </select>
    </header>

    <div class="card__body">
      <div class="base-block">
        <div class="base-block__head">
          <span class="base-block__title">社保基数</span>
          <div class="segmented" role="radiogroup" aria-label="社保基数模式">
            <button
              type="button"
              :class="{ active: state.socialBaseMode === 'auto' }"
              @click="state.socialBaseMode = 'auto'"
            >
              自动
            </button>
            <button
              type="button"
              :class="{ active: state.socialBaseMode === 'manual' }"
              @click="state.socialBaseMode = 'manual'"
            >
              手动
            </button>
          </div>
        </div>
        <div class="base-block__row">
          <NumberField
            v-model="state.social.socialBase"
            :min="state.social.socialBaseMin"
            :max="state.social.socialBaseMax"
            :disabled="state.socialBaseMode === 'auto'"
            class="base-block__field"
          />
          <span class="base-block__meta">
            区间 {{ state.social.socialBaseMin }} – {{ state.social.socialBaseMax }}
          </span>
        </div>
        <p v-if="state.socialBaseMode === 'auto'" class="auto-hint">
          勾选「社保」的收入合计
          <strong class="num">{{ formatMoney(suggestedSocial) }}</strong> 元
        </p>
      </div>

      <div class="base-block">
        <div class="base-block__head">
          <span class="base-block__title">公积金基数</span>
          <div class="segmented" role="radiogroup" aria-label="公积金基数模式">
            <button
              type="button"
              :class="{ active: state.housingFundBaseMode === 'auto' }"
              @click="state.housingFundBaseMode = 'auto'"
            >
              自动
            </button>
            <button
              type="button"
              :class="{ active: state.housingFundBaseMode === 'manual' }"
              @click="state.housingFundBaseMode = 'manual'"
            >
              手动
            </button>
          </div>
        </div>
        <div class="base-block__row">
          <NumberField
            v-model="state.social.housingFundBase"
            :min="state.social.housingFundBaseMin"
            :max="state.social.housingFundBaseMax"
            :disabled="state.housingFundBaseMode === 'auto'"
            class="base-block__field"
          />
          <span class="base-block__meta">
            区间 {{ state.social.housingFundBaseMin }} – {{ state.social.housingFundBaseMax }}
          </span>
        </div>
        <p v-if="state.housingFundBaseMode === 'auto'" class="auto-hint">
          勾选「公积金」的收入合计
          <strong class="num">{{ formatMoney(suggestedFund) }}</strong> 元
        </p>
      </div>

      <p v-if="basesDiffer" class="differ-note">
        两个基数不同（社保 {{ formatMoney(socialBaseUsed) }} / 公积金 {{ formatMoney(fundBaseUsed) }}），
        这是允许的，很多公司就是这样申报。
      </p>

      <div class="grid">
        <div class="field">
          <span class="field__label">养老保险</span>
          <NumberField v-model="state.social.pensionRate" mode="percent" :max="0.3" />
        </div>
        <div class="field">
          <span class="field__label">医疗保险</span>
          <NumberField v-model="state.social.medicalRate" mode="percent" :max="0.3" />
        </div>
        <div class="field">
          <span class="field__label">失业保险</span>
          <NumberField v-model="state.social.unemploymentRate" mode="percent" :max="0.1" />
        </div>
        <div class="field">
          <span class="field__label">住房公积金</span>
          <NumberField v-model="state.social.housingFundRate" mode="percent" :max="0.24" />
        </div>
        <div class="field">
          <span class="field__label">大额医疗互助（固定）</span>
          <NumberField v-model="state.social.medicalExtra" />
        </div>
        <div class="field field--preview">
          <span class="field__label">合计扣除（预估）</span>
          <strong class="preview num">{{ formatMoney(previewTotal) }} 元</strong>
        </div>
      </div>

      <div class="summary">
        <span>社保 <strong class="num">{{ formatMoney(socialTotal) }}</strong></span>
        <span class="dot">+</span>
        <span>公积金 <strong class="num">{{ formatMoney(fundTotal) }}</strong></span>
        <span class="dot">=</span>
        <span>合计 <strong class="num">{{ formatMoney(previewTotal) }}</strong> 元</span>
      </div>

      <p class="disclaimer">
        基数为示例默认值，请以当地人社局最新公布为准；所有比例均可直接修改。
      </p>
    </div>
  </section>
</template>

<style scoped>
/* 分段控件由 global.css 统一提供，这里只留布局 */

.base-block {
  padding: 12px;
  border-radius: var(--radius-control);
  background: var(--glass-2);
  border: 1px solid var(--border);
}

.base-block + .base-block {
  margin-top: 10px;
}

.base-block__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 8px;
}

.base-block__title {
  font-size: var(--fs-label);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-label);
  color: var(--text-strong);
}

.base-block__row {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.base-block__field {
  width: 160px;
}

.base-block__meta {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.auto-hint {
  margin: 8px 0 0;
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.auto-hint strong {
  font-weight: var(--fw-semibold);
  color: var(--text-strong);
}

.differ-note {
  margin: 10px 0 0;
  padding: 8px 10px;
  border-radius: var(--radius-sm);
  background: var(--accent-soft);
  color: var(--accent-strong);
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(148px, 1fr));
  gap: 14px 16px;
  margin-top: 16px;
  padding-top: 14px;
  border-top: 1px solid var(--divider);
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

.field--preview {
  justify-content: flex-end;
}

.preview {
  display: flex;
  align-items: center;
  height: 34px;
  color: var(--negative);
  font-size: var(--fs-heading);
  font-weight: var(--fw-semibold);
}

.summary {
  display: flex;
  align-items: baseline;
  gap: 8px;
  flex-wrap: wrap;
  margin-top: 14px;
  padding-top: 12px;
  border-top: 1px solid var(--divider);
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

.summary strong {
  color: var(--text-strong);
  font-size: var(--fs-body);
  font-weight: var(--fw-semibold);
}

.summary .dot {
  opacity: 0.5;
}

.disclaimer {
  margin: 16px 0 0;
  padding-top: 12px;
  border-top: 1px solid var(--divider);
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
  color: var(--text-muted);
}
</style>
