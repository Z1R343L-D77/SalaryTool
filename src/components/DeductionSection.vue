<script setup lang="ts">
import { computed } from "vue";
import type { DeductionItem } from "../core/calculator";
import { formatMoney, round2 } from "../core/money";
import NumberField from "./NumberField.vue";

/**
 * 其他扣除项（企业年金、请假扣款等），区分税前 / 税后。
 */
const props = defineProps<{
  items: DeductionItem[];
  presets: ReadonlyArray<Pick<DeductionItem, "label" | "preTax">>;
}>();

const emit = defineEmits<{
  add: [presetIndex: number];
  remove: [id: string];
}>();

const newPreset = defineModel<number>("newPreset", { default: 0 });

const total = computed(() => round2(props.items.reduce((sum, item) => sum + item.amount, 0)));
</script>

<template>
  <section class="card">
    <header class="card__header">
      <h2 class="card__title">
        其他扣除
        <span class="card__subtitle">税后扣款不影响个税</span>
      </h2>
      <div class="actions">
        <select v-model="newPreset" class="select select--sm" aria-label="选择扣除类型">
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
      <div v-if="items.length === 0" class="empty">暂无其他扣除项，没有可以留空。</div>

      <div v-else class="list">
        <div v-for="item in items" :key="item.id" class="row">
          <input v-model.trim="item.label" class="row__label" aria-label="扣款名称" />
          <NumberField v-model="item.amount" class="row__amount" placeholder="0.00" />
          <label class="check">
            <input v-model="item.preTax" type="checkbox" />
            <span>税前扣除</span>
          </label>
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

      <footer v-if="items.length > 0" class="total">
        扣除合计 <strong class="num">{{ formatMoney(total) }}</strong> 元
      </footer>
    </div>
  </section>
</template>

<style scoped>
.actions {
  display: flex;
  gap: 8px;
  align-items: center;
}

.select--sm {
  height: 28px;
  font-size: 12px;
}

.list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.row {
  display: grid;
  grid-template-columns: minmax(90px, 1fr) 132px auto 34px;
  gap: 8px;
  align-items: center;
  padding: 8px;
  border-radius: var(--radius-control);
  background: var(--glass-2);
}

.row__label {
  height: 34px;
  min-width: 0;
  padding: 0 10px;
  border: 1px solid transparent;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-strong);
  font-weight: 550;
  outline: 0;
}

.row__label:hover {
  background: var(--surface);
}

.row__label:focus {
  background: var(--surface);
  border-color: var(--accent);
  box-shadow: 0 0 0 3px var(--accent-soft);
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

.total {
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid var(--divider);
  text-align: right;
  font-size: 13px;
  color: var(--text-strong);
}

.empty {
  padding: 20px;
  text-align: center;
  color: var(--text-muted);
  font-size: 13px;
}

@media (max-width: 720px) {
  .row {
    grid-template-columns: 1fr 34px;
    grid-template-areas:
      "label remove"
      "amount amount"
      "flags flags";
  }
  .row__label {
    grid-area: label;
  }
  .row__amount {
    grid-area: amount;
    width: 100%;
  }
  .check {
    grid-area: flags;
  }
  .row > .btn {
    grid-area: remove;
  }
}
</style>
