<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from "vue";
import DeductionSection from "./components/DeductionSection.vue";
import ImportDialog from "./components/ImportDialog.vue";
import IncomeSection from "./components/IncomeSection.vue";
import OvertimeSection from "./components/OvertimeSection.vue";
import SettingsDialog from "./components/SettingsDialog.vue";
import SocialInsuranceSection from "./components/SocialInsuranceSection.vue";
import SpecialDeductionSection from "./components/SpecialDeductionSection.vue";
import YtdSection from "./components/YtdSection.vue";
import { formatMoney, formatRate } from "@shared/money";
import { exportState } from "@shared/storage";
import { saveFile } from "./core/platform";
import { getVersion } from "./core/version";
import {
  DEDUCTION_PRESETS,
  INCOME_PRESETS,
  addDeduction,
  addIncome,
  applyCity,
  hints,
  importState,
  hydrateFromDisk,
  removeDeduction,
  removeIncome,
  resetAll,
  result,
  selectedCity,
  state,
} from "./store/useSalaryState";

/**
 * iOS 外壳。
 *
 * 与 Windows 版共用 shared/ 里的计算与存储逻辑，界面按 iPhone 重排：
 *
 *   ┌──────────────────────────────┐
 *   │ 标题          ⚙  ⟳           │  顶部：标题 + 设置 + 导入
 *   ├──────────────────────────────┤
 *   │ 收入 专项 社保 累计 扣除 加班  │  横向可滑的分段控件（六个栏目塞不进底部标签栏）
 *   ├──────────────────────────────┤
 *   │                              │
 *   │      单列内容（滚动）          │
 *   │                              │
 *   ├──────────────────────────────┤
 *   │ 本月实发到手  ¥9,290.48   ⌃   │  底部常驻，点开看明细
 *   └──────────────────────────────┘
 *
 * 没有窗口边框、没有三色点、没有侧边栏 —— 那些是桌面才有的东西。
 */
const incomePreset = ref(0);
const deductionPreset = ref(0);
const showImport = ref(false);
const showSettings = ref(false);
const showDetail = ref(false);
const appVersion = ref("0.3.20261116");

onMounted(async () => {
  appVersion.value = await getVersion();
  // localStorage 可能被 iOS 清理过，从 App 沙盒补齐真实数据
  await hydrateFromDisk();
});

const SECTIONS = [
  { id: "income", label: "收入" },
  { id: "special", label: "专项" },
  { id: "social", label: "社保" },
  { id: "ytd", label: "累计" },
  { id: "deduction", label: "扣除" },
  { id: "overtime", label: "加班" },
] as const;

type SectionId = (typeof SECTIONS)[number]["id"];

const activeSection = ref<SectionId>("income");

/** 各栏目的角标，点在顶部时能一眼看出哪一项有数据。 */
const badges = computed<Record<SectionId, string>>(() => {
  const r = result.value;
  return {
    income: `${state.incomes.length}`,
    special: r.specialDeductionTotal > 0 ? `${r.specialDeductionTotal.toFixed(0)}` : "",
    social: r.social.total > 0 ? `${r.social.total.toFixed(0)}` : "",
    ytd: `第${state.ytd.monthIndex}月`,
    deduction: state.deductions.length ? `${state.deductions.length}` : "",
    overtime: "",
  };
});

/** 底部条上的快捷指标。 */
const quickStats = computed(() => {
  const r = result.value;
  const gross = Math.max(r.grossIncome, 0.01);
  return {
    gross: r.grossIncome,
    deduction: Math.abs(r.social.total) + r.taxThisMonth,
    netRatio: r.netPay / gross,
    tax: r.taxThisMonth,
  };
});

const toastText = ref("");
let toastTimer: ReturnType<typeof setTimeout> | undefined;

function toast(text: string): void {
  toastText.value = text;
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (toastText.value = ""), 2400);
}

function resetData(): void {
  resetAll();
  toast("已重置为示例配置");
}

const exporting = ref(false);
/** 最近一次导出的文件名，导出成功后弹提示用 */
const lastExport = ref("");
const showExportDone = ref(false);

async function exportBackup(): Promise<void> {
  if (exporting.value) return;
  exporting.value = true;
  try {
    const stamp = new Date().toISOString().slice(0, 10);
    const saved = await saveFile({
      fileName: `salarytool-backup-${stamp}.json`,
      contents: exportState(state),
    });
    if (saved.status === "saved") {
      lastExport.value = saved.fileName;
      showExportDone.value = true;
    } else if (saved.status === "downloaded") {
      toast("已下载备份文件");
    }
  } catch (error) {
    toast(`导出失败：${error instanceof Error ? error.message : String(error)}`);
  } finally {
    exporting.value = false;
  }
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
    toast("已复制");
  } catch {
    toast("复制失败");
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

/*
 * 键盘避让：iOS 弹出键盘时会把页面顶上去，但底部常驻条会被挡住。
 * 用 visualViewport 算出键盘高度，转而把底部条顶起来。
 */
const keyboardInset = ref(0);

function onViewportResize(): void {
  const vv = window.visualViewport;
  if (!vv) return;
  // 视口高度比窗口高度小多少，基本就是键盘挡住的高度
  const inset = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
  keyboardInset.value = inset > 60 ? inset : 0;
}

onMounted(() => {
  const vv = window.visualViewport;
  if (!vv) return;
  vv.addEventListener("resize", onViewportResize);
  vv.addEventListener("scroll", onViewportResize);
});

onUnmounted(() => {
  const vv = window.visualViewport;
  if (!vv) return;
  vv.removeEventListener("resize", onViewportResize);
  vv.removeEventListener("scroll", onViewportResize);
});

/** 滚动到被键盘挡住的那个输入框，避免边填边被遮住。 */
function onFieldFocus(event: FocusEvent): void {
  const el = event.target as HTMLElement | null;
  if (!el || !el.matches("input, select, textarea")) return;
  setTimeout(() => el.scrollIntoView({ block: "center", behavior: "smooth" }), 260);
}
</script>

<template>
  <div class="app" :style="{ '--keyboard-inset': keyboardInset + 'px' }">
    <header class="topbar">
      <div class="topbar__row">
        <div class="topbar__text">
          <h1 class="topbar__title">工资单</h1>
          <span class="topbar__meta">{{ selectedCity.name }} · 第 {{ state.ytd.monthIndex }} 月</span>
        </div>
        <div class="topbar__actions">
          <button class="icon-btn" type="button" aria-label="导入配置" @click="showImport = true">
            <svg viewBox="0 0 20 20" aria-hidden="true">
              <path d="M10 13.5V4M6.4 7.6 10 4l3.6 3.6M4.5 13v2.5h11V13" />
            </svg>
          </button>
          <button class="icon-btn" type="button" aria-label="设置" @click="showSettings = true">
            <svg viewBox="0 0 20 20" aria-hidden="true">
              <circle cx="10" cy="10" r="2.6" />
              <path
                d="M8.52 1.9h2.96l.34 1.72c.46.15.9.36 1.3.62l1.58-.78 2.1 2.1-.78 1.58c.26.4.47.84.62 1.3l1.72.34v2.96l-1.72.34c-.15.46-.36.9-.62 1.3l.78 1.58-2.1 2.1-1.58-.78c-.4.26-.84.47-1.3.62l-.34 1.72H8.52l-.34-1.72c-.46-.15-.9-.36-1.3-.62l-1.58.78-2.1-2.1.78-1.58a6.8 6.8 0 0 1-.62-1.3L1.9 11.48V8.52l1.72-.34c.15-.46.36-.9.62-1.3l-.78-1.58 2.1-2.1 1.58.78c.4-.26.84-.47 1.3-.62L8.52 1.9Z"
              />
            </svg>
          </button>
        </div>
      </div>
    </header>

    <!-- 六个栏目放不进 iOS 的底部标签栏，改用可横滑的分段控件 -->
    <nav class="tabs" aria-label="栏目">
      <button
        v-for="item in SECTIONS"
        :key="item.id"
        type="button"
        class="tab"
        :class="{ 'is-active': activeSection === item.id }"
        :aria-current="activeSection === item.id ? 'page' : undefined"
        @click="activeSection = item.id"
      >
        <span class="tab__label">{{ item.label }}</span>
        <span v-if="badges[item.id]" class="tab__badge num">{{ badges[item.id] }}</span>
      </button>
    </nav>

    <main class="content" @focusin="onFieldFocus">
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
      <OvertimeSection v-else :state="state" />
    </main>

    <!-- 底部常驻：实发到手永远看得见，点开展示明细 -->
    <button class="dock" type="button" :aria-expanded="showDetail" @click="showDetail = !showDetail">
      <span class="dock__left">
        <span class="dock__label">本月实发到手</span>
        <span class="dock__meta">
          税前 {{ formatMoney(quickStats.gross) }} · 扣除 {{ formatMoney(quickStats.deduction) }}
        </span>
      </span>
      <span class="dock__right">
        <span class="dock__amount num">¥{{ formatMoney(result.netPay) }}</span>
        <svg class="dock__chevron" :class="{ 'is-open': showDetail }" viewBox="0 0 16 16" aria-hidden="true">
          <path d="m4 10 4-4 4 4" />
        </svg>
      </span>
    </button>

    <Transition name="sheet">
      <div v-if="showDetail" class="sheet" @click.self="showDetail = false">
        <div class="sheet__panel">
          <div class="sheet__grip" aria-hidden="true" />
          <div class="sheet__head">
            <h2 class="sheet__title">本月明细</h2>
            <button class="btn btn--sm" type="button" @click="copySummary">复制摘要</button>
          </div>

          <dl class="kv">
            <div class="kv__row">
              <dt>税前收入</dt>
              <dd class="num">{{ formatMoney(quickStats.gross) }}</dd>
            </div>
            <div class="kv__row">
              <dt>社保 / 公积金（个人）</dt>
              <dd class="num">−{{ formatMoney(result.social.total) }}</dd>
            </div>
            <div class="kv__row">
              <dt>本月个税</dt>
              <dd class="num">−{{ formatMoney(result.taxThisMonth) }}</dd>
            </div>
            <div class="kv__row">
              <dt>实际税负率</dt>
              <dd class="num">{{ formatRate(result.effectiveTaxRate, 2) }}</dd>
            </div>
            <div class="kv__row">
              <dt>累计应纳税所得额</dt>
              <dd class="num">{{ formatMoney(result.cumulativeTaxable) }}</dd>
            </div>
            <div class="kv__row">
              <dt>累计应纳个税</dt>
              <dd class="num">{{ formatMoney(result.cumulativeTax) }}</dd>
            </div>
            <div class="kv__row kv__row--total">
              <dt>实发到手占比</dt>
              <dd class="num">{{ formatRate(quickStats.netRatio, 1) }}</dd>
            </div>
          </dl>

          <div v-if="hints.length" class="sheet__hints">
            <div v-for="hint in hints" :key="hint" class="hint">⚠ {{ hint }}</div>
          </div>

          <div class="sheet__actions">
            <button class="btn" type="button" @click="exportBackup">
              {{ exporting ? "导出中…" : "导出备份" }}
            </button>
          </div>
        </div>
      </div>
    </Transition>

    <!-- 导出成功后的说明：iOS 没有「另存为」，必须告诉用户去哪找 -->
    <Transition name="sheet">
      <div v-if="showExportDone" class="sheet" @click.self="showExportDone = false">
        <div class="sheet__panel sheet__panel--compact">
          <div class="sheet__grip" aria-hidden="true" />
          <div class="export-done">
            <span class="export-done__icon" aria-hidden="true">
              <svg viewBox="0 0 32 32">
                <circle cx="16" cy="16" r="15" fill="none" stroke="currentColor" stroke-width="1.4" />
                <path
                  d="M10 16.5 14.2 20.7 22.5 12.4"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2.1"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </span>
            <h2 class="export-done__title">已导出</h2>
            <p class="export-done__file num">{{ lastExport }}</p>
            <p class="export-done__where">
              文件保存在 App 的文档目录。打开 iPhone 上的
              <strong>「文件」</strong> App → <strong>我的 iPhone</strong> → <strong>SalaryTool</strong>，
              就能看到这个文件；长按可以拷贝或分享出去。
            </p>
            <button class="btn btn--block" type="button" @click="showExportDone = false">
              知道了
            </button>
          </div>
        </div>
      </div>
    </Transition>

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
.app {
  display: flex;
  flex-direction: column;
  height: 100%;
  /* 键盘弹出时底部条要抬起来 */
  padding-bottom: var(--keyboard-inset, 0px);
  transition: padding-bottom 180ms ease-out;
}

/* ============ 顶部：iOS 大标题 ============
   不用导航栏那种「居中标题 + 返回键」，因为这里没有层级退回。
   大标题 + 右侧两个图标按钮，是健康、提醒事项那类 App 的做法。 */

.topbar {
  flex: none;
  padding: calc(8px + env(safe-area-inset-top)) 16px 6px;
  background: transparent;
}

.topbar__row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.topbar__text {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
}

.topbar__title {
  margin: 0;
  font-size: 30px;
  font-weight: 700;
  line-height: 1.15;
  letter-spacing: -0.022em;
  color: var(--text-strong);
  white-space: nowrap;
}

.topbar__meta {
  font-size: 13px;
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.topbar__actions {
  display: flex;
  gap: 8px;
  flex: none;
}

/* iOS 的图标按钮是圆形半透明块，不是方形描边按钮 */
.icon-btn {
  display: grid;
  place-items: center;
  width: 38px;
  height: 38px;
  padding: 0;
  border: 0;
  border-radius: 50%;
  background: var(--tint-hover);
  color: var(--text-strong);
  transition: background-color 160ms ease-out, transform 140ms ease-out;
}

.icon-btn:active {
  transform: scale(0.94);
  background: var(--tint-strong);
}

.icon-btn svg {
  width: 19px;
  height: 19px;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.6;
  stroke-linecap: round;
  stroke-linejoin: round;
}

/* ============ 栏目切换 ============ */

.tabs {
  flex: none;
  display: flex;
  gap: 6px;
  padding: 10px 14px;
  overflow-x: auto;
  scrollbar-width: none;
  background: transparent;
}

.tabs::-webkit-scrollbar {
  display: none;
}

.tab {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  flex: none;
  min-height: 36px;
  padding: 0 14px;
  border: 1px solid var(--border);
  border-radius: var(--radius-pill);
  background: var(--glass-2);
  color: var(--text);
  font-size: var(--fs-label);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-label);
  white-space: nowrap;
  transition: var(--transition);
}

.tab.is-active {
  background: var(--accent);
  border-color: rgba(255, 255, 255, 0.24);
  color: #fff;
  box-shadow: 0 4px 12px -6px rgba(10, 132, 255, 0.9);
}

.tab__badge {
  font-size: var(--fs-micro);
  letter-spacing: 0;
  opacity: 0.75;
}

/* ============ 内容区 ============ */

.content {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  overscroll-behavior: contain;
  padding: 0 12px 12px;
}

/* iOS 上卡片铺满宽度，去掉桌面那层嵌套玻璃的边框感 */
.content :deep(.card) {
  border-radius: var(--radius-card);
}

.content :deep(.card__body) {
  padding: 14px;
}

/* ============ 底部常驻条 ============ */

.dock {
  flex: none;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  width: 100%;
  min-height: 64px;
  padding: 10px 16px;
  border: 0;
  border-top: 1px solid var(--border-strong);
  background: var(--glass-1);
  backdrop-filter: blur(34px) saturate(180%);
  -webkit-backdrop-filter: blur(34px) saturate(180%);
  text-align: left;
}

.dock:active {
  background: var(--glass-2);
}

.dock__left {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
}

.dock__label {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.dock__meta {
  font-size: var(--fs-micro);
  letter-spacing: var(--ls-micro);
  color: var(--text-faint);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.dock__right {
  display: flex;
  align-items: center;
  gap: 4px;
  flex: none;
}

.dock__amount {
  font-size: 23px;
  font-weight: var(--fw-semibold);
  letter-spacing: -0.02em;
  color: var(--text-strong);
}

.dock__chevron {
  width: 16px;
  height: 16px;
  fill: none;
  stroke: var(--text-muted);
  stroke-width: 1.8;
  stroke-linecap: round;
  stroke-linejoin: round;
  transition: transform 180ms ease-out;
}

.dock__chevron.is-open {
  transform: rotate(180deg);
}

/* ============ 明细面板 ============ */

.sheet {
  position: fixed;
  inset: 0;
  z-index: 110;
  display: flex;
  align-items: flex-end;
  background: var(--backdrop-dim);
  backdrop-filter: blur(6px);
  -webkit-backdrop-filter: blur(6px);
}

.sheet__panel {
  width: 100%;
  max-height: 82vh;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
  padding: 8px 16px calc(16px + env(safe-area-inset-bottom));
  border-radius: 22px 22px 0 0;
  background: var(--surface);
  border-top: 1px solid var(--border-strong);
  box-shadow: 0 -16px 48px -16px rgba(0, 0, 0, 0.6);
}

.sheet__panel--compact {
  padding-bottom: calc(20px + env(safe-area-inset-bottom));
}

.export-done {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 6px 4px 4px;
  text-align: center;
}

.export-done__icon {
  display: grid;
  place-items: center;
  width: 46px;
  height: 46px;
  margin-bottom: 2px;
  color: var(--positive);
}

.export-done__icon svg {
  width: 100%;
  height: 100%;
}

.export-done__title {
  margin: 0;
  font-size: 20px;
  font-weight: var(--fw-semibold);
  letter-spacing: -0.015em;
  color: var(--text-strong);
}

.export-done__file {
  margin: 0;
  font-size: 13px;
  color: var(--text-muted);
  word-break: break-all;
}

.export-done__where {
  margin: 4px 0 12px;
  font-size: 14px;
  line-height: 1.6;
  color: var(--text);
}

.export-done__where strong {
  color: var(--text-strong);
  font-weight: var(--fw-semibold);
}

.sheet__grip {
  width: 36px;
  height: 4px;
  margin: 0 auto 12px;
  border-radius: var(--radius-pill);
  background: var(--border-strong);
}

.sheet__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}

.sheet__title {
  margin: 0;
  font-size: var(--fs-heading);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-heading);
  color: var(--text-strong);
}

.kv {
  margin: 0;
  display: flex;
  flex-direction: column;
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  overflow: hidden;
  background: var(--glass-2);
}

.kv__row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 14px;
  font-size: var(--fs-body);
  letter-spacing: var(--ls-body);
}

.kv__row + .kv__row {
  border-top: 1px solid var(--divider);
}

.kv dt {
  color: var(--text-muted);
}

.kv dd {
  margin: 0;
  color: var(--text-strong);
  font-weight: var(--fw-medium);
}

.kv__row--total dd {
  color: var(--positive);
}

.sheet__hints {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-top: 12px;
}

.sheet__actions {
  display: flex;
  gap: 10px;
  margin-top: 16px;
}

.sheet__actions .btn {
  flex: 1;
  height: var(--tap-min);
}

.sheet-enter-active,
.sheet-leave-active {
  transition: opacity 200ms ease-out;
}

.sheet-enter-active .sheet__panel,
.sheet-leave-active .sheet__panel {
  transition: transform 220ms cubic-bezier(0.32, 0.72, 0, 1);
}

.sheet-enter-from,
.sheet-leave-to {
  opacity: 0;
}

.sheet-enter-from .sheet__panel,
.sheet-leave-to .sheet__panel {
  transform: translateY(100%);
}

/* ============ 提示 ============ */

.toast {
  position: fixed;
  left: 50%;
  bottom: calc(84px + env(safe-area-inset-bottom));
  z-index: 200;
  max-width: calc(100vw - 40px);
  padding: 10px 16px;
  border-radius: var(--radius-control);
  background: var(--menu-bg);
  backdrop-filter: blur(26px) saturate(180%);
  -webkit-backdrop-filter: blur(26px) saturate(180%);
  border: 1px solid var(--border-strong);
  box-shadow: var(--specular-top), var(--shadow-popover);
  color: var(--text-strong);
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
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

@media (prefers-reduced-motion: reduce) {
  .app {
    transition: none;
  }
}
</style>
