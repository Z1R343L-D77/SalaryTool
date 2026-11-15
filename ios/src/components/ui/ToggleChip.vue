<script setup lang="ts">
/**
 * iOS 风格的开关芯片。
 *
 * 用来替代原生复选框：一排 16px 的方块贴在卡片里，是典型的「网页移植」
 * 观感。iOS 上同样的语义一般用可点亮的胶囊标签 —— 面积大、易点中、
 * 状态靠「填充色」而不是「打勾」表达。
 */
const props = defineProps<{
  modelValue: boolean;
  label: string;
  /** 关闭状态下的说明，长按/辅助功能会读出来 */
  title?: string;
}>();

const emit = defineEmits<{ "update:modelValue": [value: boolean] }>();

function toggle(): void {
  emit("update:modelValue", !props.modelValue);
}
</script>

<template>
  <button
    type="button"
    class="chip"
    :class="{ 'is-on': modelValue }"
    role="switch"
    :aria-checked="modelValue"
    :title="title ?? label"
    @click="toggle"
  >
    {{ label }}
  </button>
</template>

<style scoped>
.chip {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  /* iOS HIG：最小触摸目标 44pt，但一排三个不能太占高度，取 32 */
  min-height: 32px;
  padding: 0 12px;
  border: 0;
  border-radius: var(--radius-pill);
  /* 关闭态：极淡的填充，不用描边（描边在 iOS 上很少见） */
  background: var(--tint-hover);
  color: var(--text-muted);
  font-size: var(--fs-label);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-label);
  white-space: nowrap;
  transition:
    background-color 180ms ease-out,
    color 180ms ease-out,
    transform 140ms ease-out;
}

/* 按下时轻微缩小，模拟 iOS 的触摸反馈 */
.chip:active {
  transform: scale(0.96);
}

.chip.is-on {
  background: var(--accent);
  color: #fff;
  font-weight: var(--fw-semibold);
  box-shadow: 0 2px 10px -4px var(--accent);
}

@media (prefers-reduced-motion: reduce) {
  .chip {
    transition: none;
  }
  .chip:active {
    transform: none;
  }
}
</style>
