<script setup lang="ts">
import { computed } from "vue";
import type { SalaryState } from "../core/defaults";
import { sumSpecialDeductions } from "../core/calculator";
import { formatMoney } from "../core/money";
import NumberField from "./NumberField.vue";

/**
 * 专项附加扣除：按月填写，累计预扣时会按「月数 × 每月金额」累计。
 */
const props = defineProps<{ state: SalaryState }>();

const FIELDS = [
  { key: "childrenEducation", label: "子女教育", hint: "2000 元/月/子女" },
  { key: "continuingEducation", label: "继续教育", hint: "400 元/月" },
  { key: "infantCare", label: "婴幼儿照护", hint: "2000 元/月/婴幼儿" },
  { key: "housingLoanInterest", label: "住房贷款利息", hint: "1000 元/月" },
  { key: "housingRent", label: "住房租金", hint: "1500 / 1100 / 800 元/月" },
  { key: "elderlyCare", label: "赡养老人", hint: "3000 元/月（独生）" },
  { key: "seriousIllness", label: "大病医疗", hint: "年度汇算，一般填 0" },
] as const;

const total = computed(() => sumSpecialDeductions(props.state.special));
</script>

<template>
  <section class="card">
    <header class="card__header">
      <h2 class="card__title">
        专项附加扣除
        <span class="card__subtitle">每月金额，减少应纳税所得额</span>
      </h2>
      <span class="total">合计 <strong class="num">{{ formatMoney(total) }}</strong> 元/月</span>
    </header>

    <div class="card__body">
      <div class="grid">
        <label v-for="field in FIELDS" :key="field.key" class="field">
          <span class="field__label">{{ field.label }}</span>
          <NumberField v-model="state.special[field.key]" placeholder="0.00" />
          <span class="field__hint">{{ field.hint }}</span>
        </label>
      </div>

      <p class="tip">
        同一项扣除在家庭成员间需按约定分摊，这里只填你本人可享受的金额。
      </p>
    </div>
  </section>
</template>

<style scoped>
.total {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
  white-space: nowrap;
}

.total strong {
  color: var(--positive);
  font-size: var(--fs-subhead);
  font-weight: var(--fw-semibold);
}

.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
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
