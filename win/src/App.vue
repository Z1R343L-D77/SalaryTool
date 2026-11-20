<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import DeductionSection from "./components/DeductionSection.vue";
import ImportDialog from "./components/ImportDialog.vue";
import IncomeSection from "./components/IncomeSection.vue";
import MealAllowanceSection from "./components/MealAllowanceSection.vue";
import OvertimeSection from "./components/OvertimeSection.vue";
import ResultPanel from "./components/ResultPanel.vue";
import SettingsDialog from "./components/SettingsDialog.vue";
import SocialInsuranceSection from "./components/SocialInsuranceSection.vue";
import SpecialDeductionSection from "./components/SpecialDeductionSection.vue";
import YtdSection from "./components/YtdSection.vue";
import { exportState } from "@shared/storage";
import { saveFile } from "./core/platform";
import { getVersion } from "./core/version";
import { closeWindow, minimizeWindow, toggleMaximizeOnDoubleClick, toggleMaximizeWindow } from "./core/window";
import {
  DEDUCTION_PRESETS,
  INCOME_PRESETS,
  addDeduction,
  addIncome,
  applyCity,
  hints,
  importState,
  removeDeduction,
  removeIncome,
  resetAll,
  result,
  selectedCity,
  state,
} from "./store/useSalaryState";

const incomePreset = ref(0);
const deductionPreset = ref(0);
const showImport = ref(false);
const showSettings = ref(false);

const appVersion = ref("0.3.20261120");

onMounted(async () => {
  appVersion.value = await getVersion();
});

/** 侧边栏栏目：左侧选中哪一项，中间就只显示哪一项。 */
const SECTIONS = [
  { id: "income", label: "收入项", hint: "工资 · 补贴 · 绩效" },
  { id: "special", label: "专项附加扣除", hint: "租房 · 教育 · 赡养" },
  { id: "social", label: "社保 / 公积金", hint: "基数 · 比例" },
  { id: "ytd", label: "累计数据", hint: "按月记录 · 年终奖" },
  { id: "deduction", label: "其他扣除", hint: "年金 · 请假扣款" },
  { id: "overtime", label: "加班费", hint: "1.5 / 2 / 3 倍" },
  { id: "meal", label: "误餐补贴", hint: "工作日 · 周末 · 出差" },
] as const;

type SectionId = (typeof SECTIONS)[number]["id"];

const activeSection = ref<SectionId>("income");
const activeMeta = computed(() => SECTIONS.find((s) => s.id === activeSection.value) ?? SECTIONS[0]);

/** 重置工资数据（外观设置保留）。由设置面板里的「重置所有数据」调用。 */
function resetData(): void {
  resetAll();
  toast("已重置为示例配置");
}

async function copySummary(): Promise<void> {
  const r = result.value;
  const lines = [
    `税前收入：${r.grossIncome.toFixed(2)} 元`,
    `社保公积金（个人）：${r.social.total.toFixed(2)} 元`,
    `本月个税：${r.taxThisMonth.toFixed(2)} 元`,
    `实发到手：${r.netPay.toFixed(2)} 元`,
  ];
  const text = `【工资到手计算】\n${lines.join("\n")}\n（城市：${selectedCity.value.name}，第 ${state.ytd.monthIndex} 月）`;
  try {
    await navigator.clipboard.writeText(text);
    toast("已复制到剪贴板");
  } catch {
    toast("复制失败，请手动选择文本");
  }
}

const toastText = ref("");
let toastTimer: ReturnType<typeof setTimeout> | undefined;

function toast(text: string): void {
  toastText.value = text;
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (toastText.value = ""), 2600);
}

const exporting = ref(false);

async function downloadBackup(): Promise<void> {
  if (exporting.value) return;
  exporting.value = true;
  try {
    const stamp = new Date().toISOString().slice(0, 10);
    const saved = await saveFile({
      fileName: `salarytool-backup-${stamp}.json`,
      contents: exportState(state),
      filters: [{ name: "工资配置", extensions: ["json"] }],
    });
    if (saved.status === "saved") {
      toast(`已保存到 ${saved.path}`);
    } else if (saved.status === "downloaded") {
      toast("已下载备份文件");
    }
  } catch (error) {
    toast(`导出失败：${error instanceof Error ? error.message : String(error)}`);
  } finally {
    exporting.value = false;
  }
}

function handleImport(payload: string): void {
  try {
    importState(payload);
    showImport.value = false;
    toast("配置已导入");
  } catch (error) {
    toast(`导入失败：${error instanceof Error ? error.message : String(error)}`);
  }
}

/** 各栏目的角标：显示与该项相关的关键数字。 */
const badges = computed<Record<SectionId, string>>(() => {
  const r = result.value;
  return {
    income: `${state.incomes.length} 项`,
    special: r.specialDeductionTotal > 0 ? `${r.specialDeductionTotal.toFixed(0)}` : "—",
    social: `${r.social.total.toFixed(0)}`,
    ytd: `第 ${state.ytd.monthIndex} 月`,
    deduction: state.deductions.length ? `${state.deductions.length} 项` : "—",
    overtime: "—",
    meal: "—",
  };
});

async function onMaximize(): Promise<void> {
  await toggleMaximizeWindow();
}
</script>

<template>
  <div class="window">
    <!-- —— 标题栏：自绘三色点 + 可拖拽 —— -->
    <header class="titlebar" @dblclick="toggleMaximizeOnDoubleClick">
      <div class="traffic" role="group" aria-label="窗口控制">
        <button class="traffic__dot traffic__dot--close" type="button" title="关闭" @click="closeWindow">
          <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3.5 3.5l5 5M8.5 3.5l-5 5" /></svg>
        </button>
        <button class="traffic__dot traffic__dot--min" type="button" title="最小化" @click="minimizeWindow">
          <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3 6h6" /></svg>
        </button>
        <button class="traffic__dot traffic__dot--max" type="button" title="最大化" @click="onMaximize">
          <svg viewBox="0 0 12 12" aria-hidden="true"><path d="M3.5 3.5h5v5h-5z" /></svg>
        </button>
      </div>

      <div class="titlebar__title">
        <span class="titlebar__app">当月薪水到手计算器</span>
        <span class="titlebar__sep">·</span>
        <span class="titlebar__section">{{ activeMeta.label }}</span>
      </div>

      <div class="titlebar__actions">
        <span class="pill">{{ selectedCity.name }} · 第 {{ state.ytd.monthIndex }} 月</span>
        <button class="btn btn--sm" type="button" @click="copySummary">复制摘要</button>
        <button class="btn btn--sm" type="button" @click="showImport = true">导入</button>
        <button class="btn btn--sm" type="button" :disabled="exporting" @click="downloadBackup">
          {{ exporting ? "导出中…" : "导出" }}
        </button>
      </div>
    </header>

    <div class="body">
      <!-- —— 侧边栏：切换中间栏目的显示 —— -->
      <aside class="sidebar glass">
        <div class="sidebar__brand">
          <h1 class="sidebar__title">工资单</h1>
          <p class="sidebar__sub">本月到手计算</p>
        </div>

        <nav class="nav" aria-label="栏目">
          <button
            v-for="item in SECTIONS"
            :key="item.id"
            type="button"
            class="nav__row"
            :class="{ 'is-active': activeSection === item.id }"
            :aria-current="activeSection === item.id ? 'page' : undefined"
            @click="activeSection = item.id"
          >
            <span class="nav__text">
              <span class="nav__label">{{ item.label }}</span>
              <span class="nav__hint">{{ item.hint }}</span>
            </span>
            <span class="nav__badge num">{{ badges[item.id] }}</span>
          </button>
        </nav>

        <div class="sidebar__foot">
          <!-- 仿常见桌面应用的底栏：左边身份 + 右边设置入口 -->
          <div class="account">
            <span class="account__avatar" aria-hidden="true">
              <svg viewBox="0 0 32 32">
                <defs>
                  <linearGradient id="sideBrand" x1="0" y1="0" x2="1" y2="1">
                    <stop offset="0%" stop-color="#5aa8ff" />
                    <stop offset="100%" stop-color="#0a6cff" />
                  </linearGradient>
                </defs>
                <rect width="32" height="32" rx="9" fill="url(#sideBrand)" />
                <path
                  d="M10.5 9.5 16 18.5 21.5 9.5M16 18.5V23M12.6 17h6.8M12.6 20.4h6.8"
                  fill="none"
                  stroke="#fff"
                  stroke-width="1.9"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </span>
            <span class="account__text">
              <span class="account__name">工资单</span>
              <span class="account__meta">v{{ appVersion }}</span>
            </span>
            <button
              class="btn btn--ghost btn--icon account__settings"
              type="button"
              title="设置"
              aria-label="设置"
              :aria-expanded="showSettings"
              @click="showSettings = true"
            >
              <svg viewBox="0 0 20 20" aria-hidden="true">
                <circle cx="10" cy="10" r="2.6" />
                <path
                  d="M8.52 1.9h2.96l.34 1.72c.46.15.9.36 1.3.62l1.58-.78 2.1 2.1-.78 1.58c.26.4.47.84.62 1.3l1.72.34v2.96l-1.72.34c-.15.46-.36.9-.62 1.3l.78 1.58-2.1 2.1-1.58-.78c-.4.26-.84.47-1.3.62l-.34 1.72H8.52l-.34-1.72c-.46-.15-.9-.36-1.3-.62l-1.58.78-2.1-2.1.78-1.58a6.8 6.8 0 0 1-.62-1.3L1.9 11.48V8.52l1.72-.34c.15-.46.36-.9.62-1.3l-.78-1.58 2.1-2.1 1.58.78c.4-.26.84-.47 1.3-.62L8.52 1.9Z"
                />
              </svg>
            </button>
          </div>
        </div>
      </aside>

      <!-- —— 中间：只显示当前栏目 —— -->
      <main class="stage">
        <div :key="activeSection" class="stage__inner">
          <IncomeSection
            v-if="activeSection === 'income'"
            v-model:new-preset="incomePreset"
            :items="state.incomes"
            :presets="INCOME_PRESETS"
            @add="addIncome"
            @remove="removeIncome"
          />
          <SpecialDeductionSection v-else-if="activeSection === 'special'" :state="state" />
          <SocialInsuranceSection
            v-else-if="activeSection === 'social'"
            :state="state"
            @apply-city="applyCity"
          />
          <YtdSection v-else-if="activeSection === 'ytd'" :state="state" />
          <DeductionSection
            v-else-if="activeSection === 'deduction'"
            v-model:new-preset="deductionPreset"
            :items="state.deductions"
            :presets="DEDUCTION_PRESETS"
            @add="addDeduction"
            @remove="removeDeduction"
          />
          <OvertimeSection v-else-if="activeSection === 'overtime'" :state="state" />
          <MealAllowanceSection v-else :state="state" />
        </div>
      </main>

      <!-- —— 右侧：始终显示汇总 —— -->
      <aside class="summary">
        <ResultPanel :result="result" :month-index="state.ytd.monthIndex" :hints="hints" />
      </aside>
    </div>

    <ImportDialog :open="showImport" @close="showImport = false" @import="handleImport" />

    <SettingsDialog
      :open="showSettings"
      :version="appVersion"
      :on-reset-data="resetData"
      @close="showSettings = false"
    />

    <Transition name="toast">
      <div v-if="toastText" class="toast" role="status" aria-live="polite">{{ toastText }}</div>
    </Transition>
  </div>
</template>

<style scoped>
/* ============ 无边框窗口外壳 ============ */

.window {
  display: flex;
  flex-direction: column;
  height: 100vh;
  border-radius: var(--radius-window);
  overflow: hidden;
  background: transparent;
  /* 系统透明窗口下自己描一圈极淡的边，让窗口边缘可辨 */
  box-shadow: inset 0 0 0 1px var(--window-edge);
}

/* ============ 标题栏 ============ */

.titlebar {
  flex: none;
  display: flex;
  align-items: center;
  gap: 12px;
  height: 46px;
  padding: 0 14px;
  background: var(--glass-1);
  backdrop-filter: blur(40px) saturate(170%);
  -webkit-backdrop-filter: blur(40px) saturate(170%);
  border-bottom: 1px solid var(--divider);
  /* 整个标题栏可拖动窗口 */
  -webkit-app-region: drag;
}

.titlebar button,
.titlebar .pill {
  -webkit-app-region: no-drag;
}

.traffic {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: none;
}

.traffic__dot {
  position: relative;
  width: 12px;
  height: 12px;
  padding: 0;
  border: 0;
  border-radius: var(--radius-pill);
  /* 三色常驻：和 macOS 一致，只有窗口失焦时才变灰 */
  box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.25);
  transition: filter 200ms ease-out, opacity 200ms ease-out;
}

.traffic__dot--close {
  background: #ff5f57;
}
.traffic__dot--min {
  background: #febc2e;
}
.traffic__dot--max {
  background: #28c840;
}

.traffic__dot svg {
  position: absolute;
  inset: 0;
  width: 12px;
  height: 12px;
  opacity: 0;
  transition: opacity 120ms ease-out;
}

.traffic__dot svg path {
  fill: none;
  stroke: rgba(0, 0, 0, 0.6);
  stroke-width: 1.5;
  stroke-linecap: round;
  stroke-linejoin: round;
}

/* 悬停时微微提亮，并显示符号 */
.traffic__dot:hover {
  filter: brightness(1.12);
}

.traffic__dot:hover svg {
  opacity: 1;
}

.titlebar__title {
  display: flex;
  align-items: baseline;
  justify-content: center;
  gap: 6px;
  flex: 1;
  min-width: 0;
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
}

.titlebar__app {
  font-size: var(--fs-body);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-heading);
  color: var(--text-strong);
}

.titlebar__sep {
  opacity: 0.35;
}

.titlebar__section {
  font-weight: var(--fw-medium);
  color: var(--text-strong);
}

.titlebar__actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: none;
}

.pill {
  display: inline-flex;
  align-items: center;
  height: 24px;
  padding: 0 10px;
  border-radius: var(--radius-pill);
  background: var(--accent-soft);
  border: 1px solid rgba(10, 132, 255, 0.24);
  color: var(--accent-strong);
  font-size: var(--fs-caption);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-caption);
  white-space: nowrap;
}

/* ============ 主体三列 ============ */

.body {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: 232px minmax(0, 1fr) 372px;
  gap: 12px;
  padding: 12px;
}

/* —— 侧边栏 —— */

.sidebar {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 14px 10px;
  border-radius: var(--radius-panel);
  min-height: 0;
  overflow-y: auto;
}

.sidebar__brand {
  padding: 2px 8px 8px;
}

.sidebar__title {
  margin: 0;
  font-size: var(--fs-title);
  font-weight: var(--fw-semibold);
  line-height: var(--lh-title);
  letter-spacing: var(--ls-title);
  color: var(--text-strong);
}

.sidebar__sub {
  margin: 3px 0 0;
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.nav {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.nav__row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  min-height: 46px;
  padding: 7px 10px;
  border: 1px solid transparent;
  border-radius: var(--radius-control);
  background: transparent;
  color: var(--text);
  text-align: left;
  transition: var(--transition);
}

.nav__row:hover {
  background-color: var(--glass-hover);
  border-color: var(--border);
}

.nav__row.is-active {
  background: var(--glass-raised);
  border-color: var(--border-strong);
  box-shadow: inset 0 1px 0 var(--hero-highlight), 0 10px 24px -14px rgba(0, 0, 0, 0.6);
  color: var(--text-strong);
}

.nav__text {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
}

.nav__label {
  font-size: var(--fs-body);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-body);
}

.nav__hint {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-faint);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.nav__row.is-active .nav__hint {
  color: var(--text-muted);
}

.nav__badge {
  flex: none;
  font-size: var(--fs-caption);
  letter-spacing: 0;
  color: var(--text-faint);
}

.nav__row.is-active .nav__badge {
  color: var(--accent-strong);
}

.sidebar__foot {
  margin-top: auto;
  padding-top: 10px;
  border-top: 1px solid var(--divider);
}

/* —— 底栏：左下角身份 + 右边设置 —— */

.account {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 4px 4px 2px;
  border-radius: var(--radius-control);
  transition: var(--transition);
}

.account:hover {
  background-color: var(--glass-hover);
}

.account__avatar {
  flex: none;
  width: 26px;
  height: 26px;
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
}

.account__avatar svg {
  display: block;
  width: 100%;
  height: 100%;
}

.account__text {
  display: flex;
  flex-direction: column;
  gap: 0;
  min-width: 0;
  flex: 1;
}

.account__name {
  font-size: var(--fs-label);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-label);
  color: var(--text-strong);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.account__meta {
  font-size: var(--fs-micro);
  letter-spacing: 0;
  color: var(--text-faint);
}

.account__settings {
  flex: none;
}

.account__settings svg {
  width: 15px;
  height: 15px;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.4;
  stroke-linecap: round;
}

/* 设置面板打开时齿轮保持高亮，便于一眼看出面板来自哪里 */
.account__settings[aria-expanded="true"] {
  color: var(--text-strong);
  background-color: var(--glass-active);
}

/* —— 中间舞台：每次只挂载一个栏目 —— */

.stage {
  min-width: 0;
  min-height: 0;
  overflow-y: auto;
  padding-right: 2px;
}

.stage__inner {
  display: flex;
  flex-direction: column;
  gap: 12px;
  animation: stage-in 200ms ease-out;
}

@keyframes stage-in {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}

/* —— 右侧汇总 —— */

.summary {
  min-width: 0;
  min-height: 0;
  overflow-y: auto;
  padding-right: 2px;
}

/* ============ 弹窗 ============ */

.modal {
  position: fixed;
  inset: 0;
  z-index: 100;
  display: grid;
  place-items: center;
  padding: 20px;
  background: var(--backdrop-dim);
  backdrop-filter: blur(6px);
}

.modal__panel {
  width: min(400px, 100%);
  padding: 20px;
  border-radius: var(--radius-panel);
  box-shadow: var(--specular-top), var(--specular-rim), var(--shadow-popover);
}

.modal__title {
  margin: 0 0 8px;
  font-size: var(--fs-heading);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-heading);
  color: var(--text-strong);
}

.modal__text {
  margin: 0 0 16px;
  font-size: var(--fs-body);
  color: var(--text-muted);
}

.modal__actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}

/* ============ 提示 ============ */

.toast {
  position: fixed;
  left: 50%;
  bottom: 24px;
  z-index: 200;
  max-width: min(560px, calc(100vw - 40px));
  padding: 10px 15px;
  border-radius: var(--radius-control);
  background: var(--menu-bg);
  backdrop-filter: blur(26px) saturate(180%);
  border: 1px solid var(--border-strong);
  box-shadow: var(--specular-top), var(--shadow-popover);
  color: var(--text-strong);
  font-size: var(--fs-label);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-label);
  line-height: var(--lh-body);
  transform: translateX(-50%);
  word-break: break-all;
}

.toast-enter-active,
.toast-leave-active {
  transition: opacity 200ms ease-out;
}

.toast-enter-from,
.toast-leave-to {
  opacity: 0;
}

/* ============ 响应式 ============ */

@media (max-width: 1180px) {
  .body {
    grid-template-columns: 210px minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr) auto;
  }
  .summary {
    grid-column: 1 / -1;
    max-height: 42vh;
  }
}

@media (max-width: 880px) {
  .body {
    grid-template-columns: minmax(0, 1fr);
  }
  .sidebar {
    display: none;
  }
  .titlebar__title {
    display: none;
  }
}
</style>
