<script setup lang="ts">
import { ref } from "vue";

/**
 * 导入配置弹窗：粘贴 JSON 文本，或选择一个 .json 文件。
 */
const props = defineProps<{ open: boolean }>();

const emit = defineEmits<{
  close: [];
  import: [payload: string];
}>();

const text = ref("");
const error = ref("");
const fileName = ref("");
const busy = ref(false);

function reset(): void {
  text.value = "";
  error.value = "";
  fileName.value = "";
  busy.value = false;
}

function close(): void {
  reset();
  emit("close");
}

async function onPickFile(event: Event): Promise<void> {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  try {
    busy.value = true;
    text.value = await file.text();
    fileName.value = file.name;
    error.value = "";
  } catch {
    error.value = "读取文件失败，请重试";
  } finally {
    busy.value = false;
    input.value = "";
  }
}

function submit(): void {
  const content = text.value.trim();
  if (!content) {
    error.value = "请先粘贴配置内容，或选择一个配置文件";
    return;
  }
  try {
    // 先在这里校验一次格式，错误留在弹窗里显示
    const parsed = JSON.parse(content) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("配置内容应该是一个 JSON 对象");
    }
    error.value = "";
    emit("import", content);
    reset();
  } catch (err) {
    error.value = err instanceof Error && err.message.includes("JSON 对象")
      ? err.message
      : "不是合法的 JSON，请检查是否漏了括号或引号";
  }
}
</script>

<template>
  <div v-if="props.open" class="modal" role="dialog" aria-modal="true" @click.self="close">
    <div class="modal__panel">
      <header class="modal__head">
        <h2 class="modal__title">导入配置</h2>
        <button class="btn btn--ghost btn--icon" type="button" title="关闭" @click="close">✕</button>
      </header>

      <p class="modal__text">
        粘贴配置文件内容，或选择 <code>.json</code> 文件。导入后会覆盖当前所有输入，并替换已保存的数据。
      </p>

      <label class="file">
        <input type="file" accept=".json,application/json" :disabled="busy" @change="onPickFile" />
        <span class="btn btn--sm">选择文件…</span>
        <span class="file__name">{{ fileName || "未选择文件" }}</span>
      </label>

      <textarea
        v-model="text"
        class="editor"
        spellcheck="false"
        placeholder='{ "cityId": "shanghai", "incomes": [ … ] }'
      />

      <p v-if="error" class="error">{{ error }}</p>

      <footer class="modal__actions">
        <button class="btn" type="button" @click="close">取消</button>
        <button class="btn btn--primary" type="button" :disabled="busy" @click="submit">导入</button>
      </footer>
    </div>
  </div>
</template>

<style scoped>
.modal {
  position: fixed;
  inset: 0;
  z-index: 120;
  display: grid;
  place-items: center;
  padding: 20px;
  background: var(--backdrop-dim);
  backdrop-filter: blur(2px);
}

.modal__panel {
  width: min(620px, 100%);
  max-height: calc(100vh - 40px);
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 20px;
  border-radius: var(--radius-card);
  background: var(--surface);
  backdrop-filter: blur(40px) saturate(160%);
  -webkit-backdrop-filter: blur(40px) saturate(160%);
  border: 1px solid var(--border-strong);
  box-shadow: var(--specular-top), var(--shadow-popover);
}

.modal__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.modal__title {
  margin: 0;
  font-size: var(--fs-heading);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-heading);
  color: var(--text-strong);
}

.modal__text {
  margin: 0;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  line-height: var(--lh-body);
  color: var(--text-muted);
}

.modal__text code {
  padding: 1px 4px;
  border-radius: 4px;
  background: var(--glass-1);
  font-family: var(--font-mono);
  font-size: var(--fs-caption);
}

.file {
  position: relative;
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

.file input[type="file"] {
  position: absolute;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
}

.file__name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.editor {
  flex: 1;
  min-height: 220px;
  max-height: 46vh;
  padding: 12px;
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  background: var(--tint-inset-strong);
  color: var(--text-strong);
  font-family: var(--font-mono);
  font-size: var(--fs-label);
  line-height: 1.65;
  letter-spacing: 0;
  resize: vertical;
  outline: 0;
  transition: var(--transition);
}

.editor:focus {
  border-color: var(--accent);
  box-shadow: 0 0 0 3px rgba(10, 132, 255, 0.3);
}

.error {
  margin: 0;
  padding: 8px 10px;
  border-radius: var(--radius-sm);
  background: var(--negative-soft);
  color: var(--negative);
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
}

.modal__actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
</style>
