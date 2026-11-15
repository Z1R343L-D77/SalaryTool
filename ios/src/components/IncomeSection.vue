<script setup lang="ts">
import { computed } from "vue";
import type { IncomeItem } from "@shared/calculator";
import { formatMoney, round2 } from "@shared/money";
import NumberField from "./NumberField.vue";
import ToggleChip from "./ui/ToggleChip.vue";

/**
 * 收入项列表（iOS 版）。
 *
 * 和桌面版的结构差别很大，不是简单压缩：
 *
 * 桌面：一行里塞下「名称 + 金额 + 三个复选框 + 删除」，靠横向空间
 * 手机：每个收入项是一张卡片 —— 名称和金额一行，三个开关一行，
 *      删除放在卡片右上角。纵向堆叠，行高放大到能点准。
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
  round2(
    props.items
      .filter((item) => item.includeInSocialBase)
      .reduce((sum, item) => sum + item.amount, 0),
  ),
);
const fundBaseTotal = computed(() =>
  round2(
    props.items
      .filter((item) => item.includeInHousingFundBase)
      .reduce((sum, item) => sum + item.amount, 0),
  ),
);
</script>

<template>
  <section class="panel">
    <header class="panel__head">
      <div>
        <h2 class="panel__title">收入项</h2>
        <p class="panel__sub">开关决定计入哪个基数、是否计税</p>
      </div>
      <span class="panel__total num">{{ formatMoney(total) }}</span>
    </header>

    <div v-if="items.length === 0" class="empty">还没有收入项</div>

    <ul v-else class="list">
      <li v-for="item in items" :key="item.id" class="row">
        <div class="row__top">
          <input
            v-model.trim="item.label"
            class="row__label"
            aria-label="收入名称"
            autocomplete="off"
          />
          <button
            class="row__remove"
            type="button"
            aria-label="删除这一项"
            @click="emit('remove', item.id)"
          >
            <svg viewBox="0 0 16 16" aria-hidden="true">
              <path d="M4 4 12 12M12 4 4 12" />
            </svg>
          </button>
        </div>

        <NumberField v-model="item.amount" class="row__amount" placeholder="0.00" />

        <div class="row__chips">
          <ToggleChip
            v-model="item.includeInSocialBase"
            label="社保"
            title="是否计入社保缴费基数"
          />
          <ToggleChip
            v-model="item.includeInHousingFundBase"
            label="公积金"
            title="是否计入公积金缴费基数"
          />
          <ToggleChip v-model="item.taxable" label="计税" title="是否计入个税应纳税所得额" />
        </div>
      </li>
    </ul>

    <footer class="add">
      <select v-model="newPreset" class="add__select" aria-label="选择收入类型">
        <option v-for="(preset, index) in presets" :key="preset.label" :value="index">
          {{ preset.label }}
        </option>
      </select>
      <button class="add__btn" type="button" @click="emit('add', newPreset)">添加</button>
    </footer>

    <dl v-if="items.length > 0" class="stats">
      <div class="stats__row">
        <dt>计入社保</dt>
        <dd class="num">{{ formatMoney(socialBaseTotal) }}</dd>
      </div>
      <div class="stats__row">
        <dt>计入公积金</dt>
        <dd class="num">{{ formatMoney(fundBaseTotal) }}</dd>
      </div>
      <div class="stats__row">
        <dt>计税收入</dt>
        <dd class="num">{{ formatMoney(taxableTotal) }}</dd>
      </div>
    </dl>
  </section>
</template>

<style scoped>
/* ============ 分组容器：iOS 的「inset grouped」观感 ============ */

.panel {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 14px 14px;
  border-radius: 18px;
  /* 半透明玻璃底，后面能看到壁纸 */
  background: var(--glass-2);
  backdrop-filter: blur(28px) saturate(170%);
  -webkit-backdrop-filter: blur(28px) saturate(170%);
  border: 0.5px solid var(--border);
}

.panel__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  padding: 0 2px;
}

.panel__title {
  margin: 0;
  font-size: 17px;
  font-weight: var(--fw-semibold);
  letter-spacing: -0.01em;
  color: var(--text-strong);
}

.panel__sub {
  margin: 2px 0 0;
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.panel__total {
  flex: none;
  font-size: 17px;
  font-weight: var(--fw-semibold);
  letter-spacing: -0.01em;
  color: var(--text-strong);
}

/* ============ 每个收入项 ============ */

.list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.row {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 12px;
  border-radius: 14px;
  /* 比容器亮一档，形成「一层压一层」的层次 */
  background: var(--tint-soft);
}

.row__top {
  display: flex;
  align-items: center;
  gap: 8px;
}

/* 名称直接可编辑，不做成输入框的样子 —— 点上去才知道能改 */
.row__label {
  flex: 1;
  min-width: 0;
  height: 28px;
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--text-strong);
  font-size: 15px;
  font-weight: var(--fw-medium);
  letter-spacing: -0.005em;
  outline: 0;
}

.row__label:focus {
  /* 聚焦时给一条底线，足够提示，又不打断视觉节奏 */
  box-shadow: inset 0 -1px 0 var(--accent);
}

.row__remove {
  display: grid;
  place-items: center;
  flex: none;
  width: 30px;
  height: 30px;
  padding: 0;
  border: 0;
  border-radius: 50%;
  background: var(--tint-hover);
  color: var(--text-muted);
  transition: background-color 160ms ease-out, color 160ms ease-out;
}

.row__remove:active {
  background: var(--negative-soft);
  color: var(--negative);
}

.row__remove svg {
  width: 14px;
  height: 14px;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.8;
  stroke-linecap: round;
}

.row__amount {
  width: 100%;
}

.row__chips {
  display: flex;
  gap: 8px;
}

/* ============ 添加 ============ */

.add {
  display: flex;
  gap: 8px;
  margin-top: 2px;
}

.add__select {
  flex: 1;
  min-width: 0;
  height: 40px;
  padding: 0 30px 0 12px;
  border: 0;
  border-radius: 12px;
  background: var(--tint-hover);
  color: var(--text-strong);
  font-size: 15px;
  appearance: none;
  /* 自定义箭头：原生 select 的箭头在深色下几乎看不见 */
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath d='M2.5 4.5 6 8l3.5-3.5' fill='none' stroke='rgba(255,255,255,0.55)' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 12px center;
}

.add__btn {
  flex: none;
  height: 40px;
  padding: 0 20px;
  border: 0;
  border-radius: 12px;
  background: var(--accent);
  color: #fff;
  font-size: 15px;
  font-weight: var(--fw-semibold);
  transition: transform 140ms ease-out, opacity 140ms ease-out;
}

.add__btn:active {
  transform: scale(0.96);
  opacity: 0.85;
}

/* ============ 汇总 ============ */

.stats {
  margin: 0;
  display: flex;
  flex-direction: column;
  border-radius: 12px;
  overflow: hidden;
  background: var(--tint-faint);
}

.stats__row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 12px;
  font-size: 14px;
}

.stats__row + .stats__row {
  border-top: 0.5px solid var(--divider);
}

.stats dt {
  color: var(--text-muted);
}

.stats dd {
  margin: 0;
  color: var(--text-strong);
  font-weight: var(--fw-medium);
}

.empty {
  padding: 28px 0;
  text-align: center;
  color: var(--text-muted);
  font-size: 14px;
}
</style>
