<script setup lang="ts">
import { computed } from "vue";
import type { IncomeItem } from "../core/calculator";
import { formatMoney, round2 } from "../core/money";
import NumberField from "./NumberField.vue";

/**
 * 收入项列表：可增删改，每项带「社保基数 / 公积金基数 / 计税」三个开关。
 *
 * 社保和公积金基数分开勾选，因为两者申报口径可能不同
 * （例如综合绩效计入社保基数，但公积金只按基本工资算）。
 */
const props = defineProps<{
  items: IncomeItem[];
  presets: ReadonlyArray<
    Pick<IncomeItem, "label" | "includeInSocialBase" | "includeInHousingFundBase" | "taxable">
  >;
}>();

const emit = defineEmits<{
  add: [presetIndex: number];
  remove: [id: string];
}>();

const newPreset = defineModel<number>("newPreset", { default: 0 });

const total = computed(() => round2(props.items.reduce((sum, item) => sum + item.amount, 0)));
const taxableTotal = computed(() =>
  round2(props.items.filter((item) => item.taxable).reduce((sum, item) => sum + item.amount, 0)),
);
const socialBaseTotal = computed(() =>
  round2(props.items.filter((item) => item.includeInSocialBase).reduce((sum, item) => sum + item.amount, 0)),
);
const fundBaseTotal = computed(() =>
  round2(props.items.filter((item) => item.includeInHousingFundBase).reduce((sum, item) => sum + item.amount, 0)),
);
</script>

<template>
  <section class="card">
    <header class="card__header">
      <h2 class="card__title">
        收入项
        <span class="card__subtitle">勾选决定计入哪个基数、是否计税</span>
      </h2>
      <div class="income-actions">
        <select v-model="newPreset" class="select select--sm" aria-label="选择收入类型">
          <option v-for="(preset, index) in presets" :key="preset.label" :value="index">
            {{ preset.label }}
          </option>
        </select>
        <button class="btn btn--sm btn--primary" type="button" @click="emit('add', newPreset)">
          + 添加
        </button>
      </div>
    </header>

    <div class="card__body">
      <div v-if="items.length === 0" class="empty">还没有收入项，点击右上角「添加」。</div>

      <div v-else class="income-list">
        <div v-for="item in items" :key="item.id" class="income-row">
          <input v-model.trim="item.label" class="income-row__label" aria-label="收入名称" />
          <NumberField v-model="item.amount" class="income-row__amount" placeholder="0.00" />
          <div class="income-row__flags">
            <label class="check" :title="item.includeInSocialBase ? '计入社保缴费基数' : '不计入社保基数'">
              <input v-model="item.includeInSocialBase" type="checkbox" />
              <span>社保</span>
            </label>
            <label class="check" :title="item.includeInHousingFundBase ? '计入公积金缴费基数' : '不计入公积金基数'">
              <input v-model="item.includeInHousingFundBase" type="checkbox" />
              <span>公积金</span>
            </label>
            <label class="check" :title="item.taxable ? '计入个税应纳税所得额' : '不计税'">
              <input v-model="item.taxable" type="checkbox" />
              <span>计税</span>
            </label>
          </div>
          <button
            class="btn btn--ghost btn--icon btn--danger"
            type="button"
            title="删除"
            @click="emit('remove', item.id)"
          >
            ✕
          </button>
        </div>
      </div>

      <footer v-if="items.length > 0" class="income-total">
        <span>收入合计 <strong class="num">{{ formatMoney(total) }}</strong> 元</span>
        <span class="income-total__muted">
          计入社保 <strong class="num">{{ formatMoney(socialBaseTotal) }}</strong>
        </span>
        <span class="income-total__muted">
          计入公积金 <strong class="num">{{ formatMoney(fundBaseTotal) }}</strong>
        </span>
        <span class="income-total__muted">
          计税 <strong class="num">{{ formatMoney(taxableTotal) }}</strong>
        </span>
      </footer>
    </div>
  </section>
</template>

<style scoped>
.income-actions {
  display: flex;
  gap: 8px;
  align-items: center;
}

.select--sm {
  height: 28px;
  font-size: 12px;
}

.income-list {
  display: flex;
  flex-direction: column;
  margin: -6px -10px;
}

.income-row {
  display: grid;
  grid-template-columns: minmax(90px, 1fr) 132px auto 26px;
  gap: 8px;
  align-items: center;
  min-height: 44px;
  padding: 0 10px;
  border-radius: var(--radius-sm);
  background: transparent;
  border-bottom: 1px solid var(--divider);
  transition: var(--transition);
}

.income-row:last-child {
  border-bottom: 0;
}

.income-row:hover {
  background: rgba(255, 255, 255, 0.06);
}

.income-row:focus-within {
  background: rgba(255, 255, 255, 0.04);
}

.income-row__label {
  height: 30px;
  min-width: 0;
  padding: 0 6px;
  border: 1px solid transparent;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-strong);
  font-weight: 500;
  outline: 0;
  transition: var(--transition);
}

.income-row__label:hover {
  background: rgba(255, 255, 255, 0.06);
}

.income-row__label:focus {
  background: var(--glass-2);
  border-color: var(--accent);
  box-shadow: 0 0 0 3px rgba(10, 132, 255, 0.28);
}

.income-row__flags {
  display: flex;
  gap: 8px;
  padding: 0 4px;
}

.check {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  color: var(--text-muted);
  font-size: 12px;
  white-space: nowrap;
  cursor: pointer;
}

.check input {
  width: 14px;
  height: 14px;
  accent-color: var(--accent);
  margin: 0;
  cursor: pointer;
}

.income-total {
  display: flex;
  flex-wrap: wrap;
  gap: 6px 16px;
  justify-content: flex-end;
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid var(--divider);
  font-size: 13px;
  color: var(--text-strong);
}

.income-total__muted {
  color: var(--text-muted);
  font-size: 12px;
}

.empty {
  padding: 24px;
  text-align: center;
  color: var(--text-muted);
  font-size: 13px;
}

@media (max-width: 720px) {
  .income-row {
    grid-template-columns: 1fr 34px;
    grid-template-areas:
      "label remove"
      "amount amount"
      "flags flags";
  }
  .income-row__label {
    grid-area: label;
  }
  .income-row__amount {
    grid-area: amount;
    width: 100%;
  }
  .income-row__flags {
    grid-area: flags;
  }
  .income-row > .btn {
    grid-area: remove;
  }
}
</style>
