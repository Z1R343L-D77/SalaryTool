<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import {
  FONT_SCALE_OPTIONS,
  THEME_OPTIONS,
  WALLPAPER_OPTIONS,
} from "../core/settings";
import { isTauri } from "../core/platform";
import { effectiveTheme, resetSettings, settings } from "../store/useSettings";

/**
 * 设置面板。
 *
 * 左边是栏目，右边是对应内容 —— 只有一个栏目时看着有点空，
 * 但外观这类设置以后只会越来越多（区域、语言、快捷键…），
 * 提前分好组比堆成一长条好找。
 */
const props = defineProps<{
  open: boolean;
  version: string;
  onResetData: () => void;
}>();

const emit = defineEmits<{ close: [] }>();

const SECTIONS = [
  { id: "appearance", label: "外观", hint: "主题 · 字号 · 壁纸" },
  { id: "data", label: "数据", hint: "重置 · 备份" },
  { id: "about", label: "关于", hint: "版本 · 许可" },
] as const;

type SectionId = (typeof SECTIONS)[number]["id"];
const active = ref<SectionId>("appearance");

const confirmReset = ref(false);

const repoUrl = "https://github.com/Z1R343L-D77/SalaryTool";

/** 主题的三个选项用一个小色块直观表达，比纯文字快。 */
const themePreview: Record<string, string> = {
  system: "linear-gradient(135deg, #1b2029 0 50%, #f4f6f9 50% 100%)",
  dark: "linear-gradient(135deg, #1b2029, #2b3442)",
  light: "linear-gradient(135deg, #f4f6f9, #dfe5ee)",
};

const themeLabel = computed(
  () => THEME_OPTIONS.find((item) => item.id === settings.theme)?.label ?? "跟随系统",
);

const currentWallpaper = computed(
  () => WALLPAPER_OPTIONS.find((item) => item.id === settings.wallpaper) ?? WALLPAPER_OPTIONS[0],
);

function doReset(): void {
  props.onResetData();
  confirmReset.value = false;
  emit("close");
}

const copied = ref(false);

async function copyRepo(): Promise<void> {
  try {
    await navigator.clipboard.writeText(repoUrl);
    copied.value = true;
    setTimeout(() => (copied.value = false), 1800);
  } catch {
    // 剪贴板不可用时忽略
  }
}

/** 桌面版能直接调 Rust 取版本号；浏览器里退回页面标题里的版本。 */
const runtime = ref("");

onMounted(() => {
  runtime.value = isTauri() ? "桌面版" : "浏览器预览";
});
</script>

<template>
  <div v-if="props.open" class="modal" role="dialog" aria-modal="true" @click.self="emit('close')">
    <div class="sheet">
      <!-- —— 左栏：分组 —— -->
      <nav class="sheet__rail" aria-label="设置分组">
        <div class="rail__brand">
          <span class="rail__avatar" aria-hidden="true">
            <svg viewBox="0 0 32 32">
              <defs>
                <linearGradient id="brandGrad" x1="0" y1="0" x2="1" y2="1">
                  <stop offset="0%" stop-color="#5aa8ff" />
                  <stop offset="100%" stop-color="#0a6cff" />
                </linearGradient>
              </defs>
              <rect width="32" height="32" rx="9" fill="url(#brandGrad)" />
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
          <span class="rail__name">
            当月薪水到手计算器
            <small>v{{ props.version }}</small>
          </span>
        </div>

        <button
          v-for="item in SECTIONS"
          :key="item.id"
          type="button"
          class="rail__row"
          :class="{ 'is-active': active === item.id }"
          @click="active = item.id"
        >
          <span class="rail__text">
            <span class="rail__label">{{ item.label }}</span>
            <span class="rail__hint">{{ item.hint }}</span>
          </span>
        </button>

        <p class="rail__foot">设置只存在本机</p>
      </nav>

      <!-- —— 右栏：内容 —— -->
      <div class="sheet__pane">
        <header class="pane__head">
          <h2 class="pane__title">{{ SECTIONS.find((s) => s.id === active)?.label }}</h2>
          <button class="btn btn--ghost btn--icon" type="button" title="关闭" @click="emit('close')">
            ✕
          </button>
        </header>

        <!-- 外观 -->
        <div v-if="active === 'appearance'" class="pane__body">
          <section class="group">
            <h3 class="group__title">主题</h3>
            <div class="theme-grid" role="radiogroup" aria-label="主题">
              <button
                v-for="option in THEME_OPTIONS"
                :key="option.id"
                type="button"
                class="theme-card"
                :class="{ 'is-active': settings.theme === option.id }"
                role="radio"
                :aria-checked="settings.theme === option.id"
                @click="settings.theme = option.id"
              >
                <span class="theme-card__swatch" :style="{ background: themePreview[option.id] }" />
                <span class="theme-card__label">{{ option.label }}</span>
              </button>
            </div>
            <p class="group__note">
              当前显示为{{ effectiveTheme === "dark" ? "深色" : "浅色" }}（{{ themeLabel }}）。
              跟随系统时会随 Windows 的深浅色设置自动切换。
            </p>
          </section>

          <section class="group">
            <h3 class="group__title">字号</h3>
            <div class="segmented" role="radiogroup" aria-label="字号">
              <button
                v-for="option in FONT_SCALE_OPTIONS"
                :key="option.id"
                type="button"
                :class="{ active: settings.fontScale === option.id }"
                @click="settings.fontScale = option.id"
              >
                {{ option.label }}
              </button>
            </div>
            <p class="group__note">
              全界面按比例缩放。屏幕大或视力不便时调大，能少眯眼；窗口不变时内容会自动换行。
            </p>
          </section>

          <section class="group">
            <h3 class="group__title">壁纸</h3>
            <div class="wallpaper-grid" role="radiogroup" aria-label="壁纸">
              <button
                v-for="option in WALLPAPER_OPTIONS"
                :key="option.id"
                type="button"
                class="wallpaper-card"
                :class="{ 'is-active': settings.wallpaper === option.id }"
                role="radio"
                :aria-checked="settings.wallpaper === option.id"
                @click="settings.wallpaper = option.id"
              >
                <span
                  class="wallpaper-card__thumb"
                  :class="`wallpaper-thumb--${option.id}`"
                  aria-hidden="true"
                />
                <span class="wallpaper-card__label">{{ option.label }}</span>
              </button>
            </div>
            <p class="group__note">{{ currentWallpaper.hint }}。</p>
          </section>

          <section class="group">
            <div class="switch-row">
              <span class="switch-row__text">
                <span class="switch-row__label">降低透明效果</span>
                <span class="switch-row__hint">
                  关掉毛玻璃模糊，壁纸只留淡淡的底纹。低配机器上更流畅，也更省电。
                </span>
              </span>
              <label class="switch">
                <input v-model="settings.reduceTransparency" type="checkbox" role="switch" />
                <span class="switch__track" aria-hidden="true" />
              </label>
            </div>
          </section>

          <button class="btn btn--sm btn--ghost" type="button" @click="resetSettings">
            恢复默认外观
          </button>
        </div>

        <!-- 数据 -->
        <div v-else-if="active === 'data'" class="pane__body">
          <section class="group">
            <h3 class="group__title">存储位置</h3>
            <p class="group__note">
              工资数据只保存在这台电脑的本地存储里，不联网、不上传。换电脑或重装系统前，
              建议先用顶栏的「导出」存一份 JSON 备份。
            </p>
          </section>

          <section class="group">
            <h3 class="group__title">重置数据</h3>
            <p class="group__note">
              清空当前填写的收入、社保、累计记录与加班数据，恢复成示例配置。外观设置不受影响。
            </p>
            <div v-if="!confirmReset" class="row-actions">
              <button class="btn btn--sm btn--danger" type="button" @click="confirmReset = true">
                重置所有数据
              </button>
            </div>
            <div v-else class="confirm">
              <p class="confirm__text">确定要清空吗？这一步不能撤销。</p>
              <div class="row-actions">
                <button class="btn btn--sm" type="button" @click="confirmReset = false">取消</button>
                <button class="btn btn--sm btn--primary" type="button" @click="doReset">
                  确认重置
                </button>
              </div>
            </div>
          </section>
        </div>

        <!-- 关于 -->
        <div v-else class="pane__body">
          <section class="group">
            <h3 class="group__title">版本</h3>
            <dl class="kv">
              <div class="kv__row">
                <dt>版本号</dt>
                <dd class="num">v{{ props.version }}</dd>
              </div>
              <div class="kv__row">
                <dt>运行环境</dt>
                <dd>{{ runtime }}</dd>
              </div>
              <div class="kv__row">
                <dt>技术栈</dt>
                <dd>Tauri 2 · Vue 3 · TypeScript</dd>
              </div>
            </dl>
          </section>

          <section class="group">
            <h3 class="group__title">源码</h3>
            <div class="repo">
              <code class="repo__url">{{ repoUrl }}</code>
              <div class="row-actions">
                <button class="btn btn--sm" type="button" @click="copyRepo">
                  {{ copied ? "已复制" : "复制链接" }}
                </button>
              </div>
            </div>
            <p class="group__note">
              MIT 许可。计算口径的说明见仓库 README，遇到的偏差可以在那里对照。
            </p>
          </section>

          <section class="group">
            <h3 class="group__title">字体</h3>
            <p class="group__note">
              Inter（拉丁字母与数字）与 Noto Sans SC（中文），均为 SIL Open Font License 1.1，
              已随程序打包，不依赖系统字体。
            </p>
          </section>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.modal {
  position: fixed;
  inset: 0;
  z-index: 140;
  display: grid;
  place-items: center;
  padding: 24px;
  background: var(--backdrop-dim);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
}

.sheet {
  display: grid;
  grid-template-columns: minmax(0, 200px) minmax(0, 1fr);
  width: min(760px, 100%);
  height: min(580px, calc(100vh - 48px));
  border-radius: var(--radius-panel);
  background: var(--surface);
  backdrop-filter: blur(40px) saturate(160%);
  -webkit-backdrop-filter: blur(40px) saturate(160%);
  border: 1px solid var(--border-strong);
  box-shadow: var(--specular-top), var(--shadow-popover);
  overflow: hidden;
}

/* —— 左栏 —— */

.sheet__rail {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 14px 10px;
  border-right: 1px solid var(--divider);
  background: var(--tint-faint);
}

.rail__brand {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 2px 8px 14px;
}

.rail__avatar {
  flex: none;
  width: 30px;
  height: 30px;
}

.rail__avatar svg {
  width: 100%;
  height: 100%;
  display: block;
}

.rail__name {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
  font-size: var(--fs-caption);
  font-weight: var(--fw-semibold);
  line-height: 1.25;
  letter-spacing: var(--ls-caption);
  color: var(--text-strong);
  /* 字号调大后标题会换行，变成两行「计算 / 器」很难看，宁可省略 */
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.rail__name small {
  font-size: var(--fs-micro);
  font-weight: var(--fw-regular);
  color: var(--text-muted);
  letter-spacing: 0;
}

.rail__row {
  display: flex;
  align-items: center;
  padding: 7px 10px;
  border: 1px solid transparent;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text);
  text-align: left;
  transition: var(--transition);
}

.rail__row:hover {
  background-color: var(--glass-hover);
}

.rail__row.is-active {
  background: var(--glass-raised);
  border-color: var(--border);
  box-shadow: inset 0 1px 0 var(--hero-highlight);
}

.rail__text {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 0;
}

.rail__label {
  font-size: var(--fs-label);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-label);
  color: var(--text-strong);
}

.rail__hint {
  font-size: var(--fs-micro);
  letter-spacing: var(--ls-micro);
  color: var(--text-faint);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.rail__foot {
  margin: auto 0 0;
  padding: 10px 8px 2px;
  font-size: var(--fs-micro);
  letter-spacing: var(--ls-micro);
  color: var(--text-faint);
}

/* —— 右栏 —— */

.sheet__pane {
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.pane__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 14px 20px;
  border-bottom: 1px solid var(--divider);
}

.pane__title {
  margin: 0;
  font-size: var(--fs-heading);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-heading);
  color: var(--text-strong);
}

.pane__body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 18px 20px 24px;
  display: flex;
  flex-direction: column;
  gap: 22px;
}

.group {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.group__title {
  margin: 0;
  font-size: var(--fs-label);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-label);
  color: var(--text);
}

.group__note {
  margin: 0;
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
  color: var(--text-muted);
}

/* —— 主题卡片 —— */

.theme-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
}

.theme-card {
  display: flex;
  flex-direction: column;
  gap: 7px;
  padding: 8px;
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  background: var(--glass-2);
  transition: var(--transition);
}

.theme-card:hover {
  border-color: var(--border-strong);
  background-color: var(--glass-hover);
}

.theme-card.is-active {
  border-color: var(--accent);
  box-shadow: 0 0 0 2px var(--accent-soft);
}

.theme-card__swatch {
  height: 46px;
  border-radius: 7px;
  border: 1px solid var(--border);
}

.theme-card__label {
  font-size: var(--fs-caption);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-caption);
  color: var(--text-strong);
  text-align: center;
}

/* —— 壁纸卡片 —— */

.wallpaper-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 10px;
}

.wallpaper-card {
  display: flex;
  flex-direction: column;
  gap: 7px;
  padding: 6px;
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  background: var(--glass-2);
  transition: var(--transition);
}

.wallpaper-card:hover {
  border-color: var(--border-strong);
}

.wallpaper-card.is-active {
  border-color: var(--accent);
  box-shadow: 0 0 0 2px var(--accent-soft);
}

.wallpaper-card__thumb {
  height: 42px;
  border-radius: 6px;
  border: 1px solid var(--border);
  background-size: cover;
  background-position: center;
}

/* 缩略图用小尺寸引用同一张图，视觉上和真实壁纸一致 */
.wallpaper-thumb--fuji {
  background-image: url("../assets/wallpaper.jpg");
  background-position: center 58%;
}

.wallpaper-thumb--aurora {
  background-image: linear-gradient(155deg, #06131f 0%, #0b2f3a 32%, #12615a 58%, #0a2333 100%);
}

.wallpaper-thumb--dusk {
  background-image: linear-gradient(160deg, #1a1030 0%, #4d2152 34%, #a34a4a 62%, #c2673f 80%, #2a1526 100%);
}

.wallpaper-thumb--plain {
  background-image: none;
  background-color: var(--bg-base);
}

.wallpaper-card__label {
  font-size: var(--fs-micro);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-micro);
  color: var(--text-strong);
  text-align: center;
}

/* —— 开关 —— */

.switch-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 14px;
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  background: var(--glass-2);
}

.switch-row__text {
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
}

.switch-row__label {
  font-size: var(--fs-body);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-body);
  color: var(--text-strong);
}

.switch-row__hint {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
  color: var(--text-muted);
}

.switch {
  position: relative;
  flex: none;
  width: 40px;
  height: 24px;
  cursor: pointer;
}

/* 隐藏原生复选框，但仍保留可聚焦与键盘操作 */
.switch input {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  margin: 0;
  opacity: 0;
  cursor: pointer;
  z-index: 1;
}

.switch__track {
  position: absolute;
  inset: 0;
  border-radius: var(--radius-pill);
  background: var(--tint-inset);
  border: 1px solid var(--border);
  transition: var(--transition);
}

.switch__track::after {
  content: "";
  position: absolute;
  top: 2px;
  left: 2px;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: #fff;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.35);
  transition: transform 180ms ease-out;
}

.switch input:checked + .switch__track {
  background: var(--accent);
  border-color: rgba(255, 255, 255, 0.24);
}

.switch input:checked + .switch__track::after {
  transform: translateX(16px);
}

.switch input:focus-visible + .switch__track {
  box-shadow: 0 0 0 3px rgba(10, 132, 255, 0.35);
}

/* —— 数据 / 关于 —— */

.row-actions {
  display: flex;
  gap: 8px;
}

.confirm {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 12px 14px;
  border: 1px solid var(--border);
  border-left: 3px solid var(--negative);
  border-radius: var(--radius-control);
  background: var(--glass-2);
}

.confirm__text {
  margin: 0;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--negative);
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
  padding: 10px 14px;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
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

.repo {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 12px 14px;
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  background: var(--glass-2);
}

.repo__url {
  font-family: var(--font-mono);
  font-size: var(--fs-caption);
  color: var(--text);
  overflow-wrap: anywhere;
}

@media (max-width: 700px) {
  .sheet {
    grid-template-columns: minmax(0, 1fr);
    grid-template-rows: auto minmax(0, 1fr);
  }
  .sheet__rail {
    flex-direction: row;
    align-items: center;
    border-right: 0;
    border-bottom: 1px solid var(--divider);
    overflow-x: auto;
  }
  .rail__brand,
  .rail__hint,
  .rail__foot {
    display: none;
  }
  .theme-grid,
  .wallpaper-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
</style>
