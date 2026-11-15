<script setup lang="ts">
import { computed, ref } from "vue";
import { round2, toAmount } from "../core/money";
/**
 * 金额 / 百分比输入框。
 *
 * - 金额模式：失焦时显示千分位与两位小数，聚焦时显示纯数字，方便编辑
 * - 百分比模式：内部存小数（0.08），界面显示 8（%）
 */
const props = withDefaults(
  defineProps<{
    modelValue: number;
    mode?: "money" | "percent";
    suffix?: string;
    min?: number;
    max?: number;
    disabled?: boolean;
    placeholder?: string;
    align?: "left" | "right";
  }>(),
  { mode: "money", min: 0, align: "right" },
);

const emit = defineEmits<{ "update:modelValue": [value: number] }>();

const focused = ref(false);
const draft = ref("");

const ratio = computed(() => (props.mode === "percent" ? 100 : 1));
const suffixText = computed(() => props.suffix ?? (props.mode === "percent" ? "%" : "元"));
const safeValue = computed(() => toAmount(props.modelValue));

function plain(value: number): string {
  const scaled = round2(value * ratio.value);
  return scaled % 1 === 0 ? String(scaled) : scaled.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
}

const moneyDisplay = new Intl.NumberFormat("zh-CN", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** 非编辑态下的展示值：金额带千分位，百分比为纯数字。 */
const formatted = computed(() =>
  props.mode === "percent" ? plain(safeValue.value) : moneyDisplay.format(round2(safeValue.value)),
);

const display = computed(() => (focused.value ? draft.value : formatted.value));

function clampValue(value: number): number {
  let next = value;
  if (props.min !== undefined) next = Math.max(props.min, next);
  if (props.max !== undefined) next = Math.min(props.max, next);
  return round2(next);
}

function onFocus(event: FocusEvent): void {
  focused.value = true;
  draft.value = plain(safeValue.value);
  requestAnimationFrame(() => (event.target as HTMLInputElement).select());
}

function onInput(event: Event): void {
  draft.value = (event.target as HTMLInputElement).value;
}

function commit(): void {
  focused.value = false;
  const parsed = toAmount(draft.value, safeValue.value * ratio.value) / ratio.value;
  emit("update:modelValue", clampValue(Number.isFinite(parsed) ? parsed : 0));
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === "Enter") (event.target as HTMLInputElement).blur();
  if (event.key === "Escape") {
    draft.value = plain(safeValue.value);
    (event.target as HTMLInputElement).blur();
  }
  if (event.key === "ArrowUp" || event.key === "ArrowDown") {
    event.preventDefault();
    // 草稿值本身就是展示单位：金额为元，百分比为百分点
    const step = props.mode === "percent" ? 0.5 : 100;
    const delta = event.key === "ArrowUp" ? step : -step;
    const next = toAmount(draft.value, 0) + delta;
    draft.value = String(Math.round(next * 100) / 100);
    emit("update:modelValue", clampValue(next / ratio.value));
  }
}
</script>

<template>
  <label class="number-field" :class="{ 'is-disabled': disabled, 'align-left': align === 'left' }">
    <span class="number-field__prefix" v-if="$slots.prefix"><slot name="prefix" /></span>
    <input
      class="number-field__input"
      type="text"
      inputmode="decimal"
      :value="display"
      :placeholder="placeholder"
      :disabled="disabled"
      @focus="onFocus"
      @input="onInput"
      @blur="commit"
      @keydown="onKeydown"
    />
    <span class="number-field__suffix">{{ suffixText }}</span>
  </label>
</template>

<style scoped>
.number-field {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  padding: 0 9px;
  height: 28px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--glass-2);
  transition: var(--transition);
}

.number-field:hover {
  border-color: var(--border-strong);
}

.number-field:focus-within {
  border-color: var(--accent);
  box-shadow: 0 0 0 3px rgba(10, 132, 255, 0.28);
}

.number-field.is-disabled {
  opacity: 0.5;
  background: transparent;
}

.number-field__input {
  flex: 1;
  min-width: 0;
  width: 100%;
  border: 0;
  outline: 0;
  background: transparent;
  color: var(--text-strong);
  font-family: var(--font-mono);
  font-size: 13px;
  font-variant-numeric: tabular-nums;
  letter-spacing: 0;
  text-align: right;
}

.align-left .number-field__input {
  text-align: left;
}

.number-field__suffix,
.number-field__prefix {
  flex: none;
  color: var(--text-muted);
  font-size: 11px;
}
</style>
