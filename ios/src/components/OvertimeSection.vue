<script setup lang="ts">
import { computed, watch } from "vue";
import type { SalaryState } from "@shared/defaults";
import { formatMoney, formatPrecise, formatRate, round2 } from "@shared/money";
import {
  HOLIDAY_RATE,
  WEEKDAY_RATE,
  WEEKEND_RATE,
  calcOvertime,
  hourlyToMonthly,
  monthlyToHourly,
  summarizeCalendarHours,
} from "@shared/overtime";
import type { OvertimeBaseMode } from "@shared/overtime";
import {
  ensureOvertimeIncome,
  findOvertimeIncome,
  setOvertimeSyncEnabled,
} from "../store/useSalaryState";
import NumberField from "./NumberField.vue";
import OvertimeCalendar from "./OvertimeCalendar.vue";

/**
 * 加班费计算器。
 *
 * 输入直接读写 store 里的 state.overtime，切换栏目不会丢失；
 * 打开「同步到收入项」后，算出的合计会自动写进指定的收入项。
 *
 * 月薪与时薪是同一枚硬币的两面：改任意一边，另一边立刻按
 * 「月薪 = 时薪 × 月计薪天数 × 日工时」重算，所以来回切换模式不会
 * 覆盖你手填的数。工时同理——日历里改了任何一天，三档合计跟着更新。
 */
const props = defineProps<{ state: SalaryState }>();

/** 加班费的输入对象（直接引用 store，改动即持久化）。 */
const input = computed(() => props.state.overtime);

const basicSalary = computed(() => {
  const basic = props.state.incomes.find((item) => item.label.includes("基本工资"));
  if (basic) return basic.amount;
  return props.state.incomes.find((item) => item.includeInSocialBase)?.amount ?? 0;
});

/** 时薪 ← 月薪（用于跟随基本工资、改月计薪天数等场景）。 */
function syncHourlyFromBase(): void {
  input.value.hourlyRate = monthlyToHourly(
    input.value.base,
    input.value.monthlyDays,
    input.value.dailyHours,
  );
}

/** 月薪 ← 时薪。 */
function syncBaseFromHourly(): void {
  input.value.base = hourlyToMonthly(
    input.value.hourlyRate,
    input.value.monthlyDays,
    input.value.dailyHours,
    input.value.base,
  );
}

// 跟随基本工资：收入项里的基本工资一变，月薪和时薪同步跟上
watch(
  basicSalary,
  (value) => {
    if (!input.value.followBasicSalary) return;
    input.value.base = value;
    syncHourlyFromBase();
  },
  { immediate: true },
);

/*
 * 老配置里时薪可能还是 0（早期版本只在切到「直接填时薪」时才写这个字段）。
 * 首次挂载时补一次：只要月薪有值、时薪为空，就按当前折算规则算出来，
 * 免得一进时薪模式看到 0。
 */
if (!input.value.followBasicSalary && input.value.hourlyRate <= 0 && input.value.base > 0) {
  syncHourlyFromBase();
}

/** 改月薪：时薪立刻反算。 */
function onBaseInput(value: number): void {
  input.value.base = value;
  syncHourlyFromBase();
  // 手填基数就不再跟随基本工资，否则下次基本工资变动会把这里覆盖掉
  input.value.followBasicSalary = false;
}

/** 改时薪：月薪立刻反算，并停止跟随基本工资。 */
function onHourlyInput(value: number): void {
  input.value.hourlyRate = value;
  syncBaseFromHourly();
  input.value.followBasicSalary = false;
}

/*
 * 月计薪天数 / 日工时属于「折算规则」，改了之后另一边要按新规则重算。
 * 跟随基本工资时以月薪为准，否则以当前正在填的那一边为准。
 */
watch(
  () => [input.value.monthlyDays, input.value.dailyHours],
  () => {
    if (input.value.followBasicSalary) {
      input.value.base = basicSalary.value;
      syncHourlyFromBase();
    } else if (input.value.mode === "hourly") {
      syncBaseFromHourly();
    } else {
      syncHourlyFromBase();
    }
  },
);

/** 可以绑定的收入项（排除加班费本身，避免自我覆盖；加班补助是另一笔钱，可以选）。 */
const candidateIncomes = computed(() => {
  const boundId = props.state.overtimeSync.incomeId;
  return props.state.incomes.filter(
    (item) => item.id === boundId || item.label.trim() !== "加班费",
  );
});

const boundIncome = computed(() => findOvertimeIncome());

function toggleAuto(value: boolean): void {
  input.value.followBasicSalary = value;
  if (value) {
    input.value.base = basicSalary.value;
    syncHourlyFromBase();
  }
}

/*
 * 切换模式只换「显示哪一个」，不重算数字 ——
 * 月薪和时薪在编辑时已经互相同步过了，这里再算一遍只会把用户刚填的值盖掉。
 *
 * 唯一要照顾的是「跟随基本工资」：这个开关只在月薪模式显示。
 * 进时薪模式时记下状态；如果用户没动过时薪，切回来就还原跟随（否则会留下
 * 3883.68 这种折算出来的怪数字）；动过的话就以他填的时薪为准。
 */
let followBeforeHourly = true;
let hourlyTouched = false;

function switchMode(mode: OvertimeBaseMode): void {
  if (input.value.mode === mode) return;
  if (mode === "hourly") {
    followBeforeHourly = input.value.followBasicSalary;
    hourlyTouched = false;
    input.value.followBasicSalary = false;
  } else if (followBeforeHourly && !hourlyTouched) {
    input.value.followBasicSalary = true;
    input.value.base = basicSalary.value;
    syncHourlyFromBase();
  }
  input.value.mode = mode;
}

function onToggleSync(event: Event): void {
  setOvertimeSyncEnabled((event.target as HTMLInputElement).checked);
}

function onChangeTarget(event: Event): void {
  const value = (event.target as HTMLSelectElement).value;
  const target = props.state.incomes.find((item) => item.id === value);
  if (!target) return;
  props.state.overtimeSync.incomeId = target.id;
}

function onCreateTarget(): void {
  ensureOvertimeIncome();
}

const calendarHours = computed(() => summarizeCalendarHours(input.value.calendar));

const calendarTotal = computed(
  () =>
    calendarHours.value.weekdayHours +
    calendarHours.value.weekendHours +
    calendarHours.value.holidayHours,
);

const manualTotal = computed(
  () => input.value.weekdayHours + input.value.weekendHours + input.value.holidayHours,
);

/**
 * 日历里任何一天的工时或档位一变，三档合计就跟着更新。
 *
 * 这样「按日历填写 → 切回直接填合计」看到的就是日历算出来的数，
 * 不需要每次切换都重新汇总一遍。
 */
function syncHoursFromCalendar(): void {
  input.value.weekdayHours = calendarHours.value.weekdayHours;
  input.value.weekendHours = calendarHours.value.weekendHours;
  input.value.holidayHours = calendarHours.value.holidayHours;
}

/*
 * 日历一改，三档合计实时跟着变，不用等切回合计模式。
 *
 * 只在日历确实有记录时才写：用户可能先在「直接填合计」里填了数、再点开日历
 * 看看，这时候用 0 去覆盖会把他刚填的内容抹掉。
 */
watch(
  () => input.value.calendar,
  () => {
    if (input.value.entryMode !== "calendar") return;
    if (calendarTotal.value <= 0) return;
    syncHoursFromCalendar();
  },
  { deep: true },
);

/**
 * 切换工时录入方式。
 *
 * 日历 → 合计：直接用日历汇总覆盖三档合计，这是「同步记录」的方向。
 * 合计 → 日历：完全不碰日历。日历是按天记的真实工时，拿模糊的合计
 * 去反推每一天只能靠猜，一旦写进去就把那些记录毁了。
 *
 * 两边不一致时由 hoursNote 在界面上说明，由用户自己决定用哪个。
 */
function switchEntryMode(mode: "manual" | "calendar"): void {
  if (input.value.entryMode === mode) return;
  if (mode === "manual" && calendarTotal.value > 0) {
    syncHoursFromCalendar();
  }
  input.value.entryMode = mode;
}

/** 日历模式下两者不一致时的说明；反过来永远不覆盖日历数据。 */
const hoursNote = computed(() => {
  if (input.value.entryMode !== "calendar") return "";
  const cal = round2(calendarTotal.value);
  const manual = round2(manualTotal.value);
  if (cal === 0 && manual > 0) {
    return `日历里还没有记录，当前按 0 小时计算；「直接填合计」里的 ${manual} 小时仍然保留，切回去即可继续用。`;
  }
  if (cal > 0 && manual > 0 && cal !== manual) {
    return `日历汇总 ${cal} 小时，与直接填写的 ${manual} 小时不同，当前按日历计算。`;
  }
  return "";
});

/** 清零只作用于当前正在用的录入方式，另一边的数据保留。 */
function resetHours(): void {
  if (input.value.entryMode === "calendar") {
    input.value.calendar.hours = {};
  } else {
    input.value.weekdayHours = 0;
    input.value.weekendHours = 0;
    input.value.holidayHours = 0;
  }
}

const result = computed(() => calcOvertime(input.value));

const TIERS = [
  { key: "weekday" as const, label: "工作日", rate: WEEKDAY_RATE, hint: "延长工时 1.5 倍" },
  { key: "weekend" as const, label: "周末", rate: WEEKEND_RATE, hint: "休息日 2 倍" },
  { key: "holiday" as const, label: "节假日", rate: HOLIDAY_RATE, hint: "法定节假日 3 倍" },
];

/** 月薪模式的折算说明：月薪 ÷ 21.75 ÷ 8 */
const formula = computed(
  () =>
    `${formatMoney(input.value.base)} ÷ ${input.value.monthlyDays} ÷ ${input.value.dailyHours} = ${formatPrecise(result.value.hourlyBase)} 元/小时`,
);

const isHourly = computed(() => input.value.mode === "hourly");
const isCalendar = computed(() => input.value.entryMode === "calendar");
const syncEnabled = computed(() => props.state.overtimeSync.enabled);

/** 折合工作日：按每日标准工时换算，帮助理解工时规模 */
const equivalentDays = computed(() =>
  input.value.dailyHours > 0 ? round2(result.value.totalHours / input.value.dailyHours) : 0,
);
</script>

<template>
  <section class="card">
    <header class="card__header">
      <h2 class="card__title">
        加班费计算器
        <span class="card__subtitle">工作日 1.5 倍 · 周末 2 倍 · 节假日 3 倍</span>
      </h2>
      <button class="btn btn--sm" type="button" @click="resetHours">清零工时</button>
    </header>

    <div class="card__body">
      <div class="mode-row">
        <span class="mode-row__label">基数方式</span>
        <div class="segmented" role="radiogroup" aria-label="基数方式">
          <button
            type="button"
            :class="{ active: !isHourly }"
            @click="switchMode('monthly')"
          >
            按月薪折算
          </button>
          <button
            type="button"
            :class="{ active: isHourly }"
            @click="switchMode('hourly')"
          >
            直接填时薪
          </button>
        </div>
      </div>

      <div class="base-row">
        <label v-if="!isHourly" class="field">
          <span class="field__label">加班费基数（元/月）</span>
          <NumberField
            :model-value="input.base"
            :disabled="input.followBasicSalary"
            class="base-row__field"
            @update:model-value="onBaseInput"
          />
          <span class="field__hint">
            折算小时工资 = {{ formula }}
          </span>
        </label>

        <label v-else class="field">
          <span class="field__label">加班费基数（元/小时）</span>
          <NumberField
            :model-value="input.hourlyRate"
            class="base-row__field"
            suffix="元/时"
            :precision="4"
            @update:model-value="onHourlyInput"
          />
          <span class="field__hint">
            时薪直乘倍率，不再按 21.75 天折算
          </span>
        </label>

        <label v-if="!isHourly" class="check">
          <input
            type="checkbox"
            :checked="input.followBasicSalary"
            @change="toggleAuto(($event.target as HTMLInputElement).checked)"
          />
          <span>跟随基本工资（{{ formatMoney(basicSalary) }}）</span>
        </label>
      </div>

      <div class="mode-row">
        <span class="mode-row__label">工时录入</span>
        <div class="segmented" role="radiogroup" aria-label="工时录入方式">
          <button
            type="button"
            :class="{ active: !isCalendar }"
            @click="switchEntryMode('manual')"
          >
            直接填合计
          </button>
          <button
            type="button"
            :class="{ active: isCalendar }"
            @click="switchEntryMode('calendar')"
          >
            按日历填写
          </button>
        </div>
      </div>

      <p v-if="hoursNote" class="hours-note">{{ hoursNote }}</p>

      <OvertimeCalendar
        v-if="input.entryMode === 'calendar'"
        :calendar="input.calendar"
        :weekday-rate="result.weekdayRate"
        :weekend-rate="result.weekendRate"
        :holiday-rate="result.holidayRate"
      />

      <div v-else class="tiers">
        <div v-for="tier in TIERS" :key="tier.key" class="tier">
          <div class="tier__head">
            <span class="tier__name">{{ tier.label }}</span>
            <span class="tier__rate">{{ formatRate(tier.rate, 1) }}</span>
          </div>
          <NumberField
            v-model="input[`${tier.key}Hours`]"
            suffix="小时"
            :max="400"
            class="tier__hours"
          />
          <div class="tier__calc">
            <span class="tier__unit">
              {{ formatPrecise(result[`${tier.key}Rate`]) }} 元/小时
            </span>
            <strong class="tier__pay num">{{ formatMoney(result[`${tier.key}Pay`]) }} 元</strong>
          </div>
          <span class="tier__hint">{{ tier.hint }}</span>
        </div>
      </div>

      <div class="total">
        <div class="total__left">
          <span class="total__label">加班费合计</span>
          <span class="total__meta">
            {{ result.totalHours }} 小时 · 折合 {{ equivalentDays }} 个工作日
          </span>
        </div>
        <strong class="total__amount num">¥{{ formatMoney(result.totalPay) }}</strong>
      </div>

      <!-- 同步到收入项 -->
      <div class="sync" :class="{ 'is-on': syncEnabled }">
        <div class="sync__head">
          <label class="check check--strong">
            <input type="checkbox" :checked="syncEnabled" @change="onToggleSync" />
            <span>同步到收入项</span>
          </label>
          <span v-if="syncEnabled" class="sync__status">
            已写入「{{ boundIncome?.label ?? "加班费" }}」
            <strong class="num">{{ formatMoney(boundIncome?.amount ?? 0) }}</strong> 元
          </span>
          <span v-else class="sync__status sync__status--off">关闭时只计算，不改动工资单</span>
        </div>

        <template v-if="syncEnabled">
          <div class="sync__row">
            <span class="sync__label">写入到</span>
            <select class="select sync__select" :value="boundIncome?.id ?? ''" @change="onChangeTarget">
              <option v-for="item in candidateIncomes" :key="item.id" :value="item.id">
                {{ item.label }}
              </option>
            </select>
            <button
              v-if="!boundIncome"
              class="btn btn--sm"
              type="button"
              @click="onCreateTarget"
            >
              新建「加班费」项
            </button>
          </div>
          <p class="sync__hint">
            工时或基数一改，金额会自动写进这一项，工资合计、社保基数与个税都会跟着重算。
          </p>
        </template>
      </div>

      <details class="details">
        <summary>计薪规则设置</summary>
        <div class="details__grid">
          <label v-if="!isHourly" class="field">
            <span class="field__label">月计薪天数</span>
            <NumberField v-model="input.monthlyDays" suffix="天" :max="31" :min="1" />
            <span class="field__hint">法定 21.75 = (365 − 104) ÷ 12</span>
          </label>
          <label class="field">
            <span class="field__label">每日标准工时</span>
            <NumberField v-model="input.dailyHours" suffix="小时" :max="24" :min="1" />
            <span class="field__hint">通常 8 小时；综合工时制可能不同</span>
          </label>
        </div>
      </details>

      <p class="disclaimer">
        <template v-if="!isHourly">
          按《劳动法》第 44 条折算：小时工资 = 月工资 ÷ 21.75 ÷ 8。
        </template>
        <template v-else>
          时薪模式：直接以填写的小时工资作为 1 倍基数。
        </template>
        休息日加班可用补休替代，法定节假日必须支付 3 倍工资。计算结果是应得金额，
        实际以公司规定和当地标准为准。
      </p>
    </div>
  </section>
</template>

<style scoped>
.mode-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;
}

.mode-row__label {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

/* 两种录入方式数据不一致时的提示：说明当前以哪一边为准 */
.hours-note {
  margin: -2px 0 12px;
  padding: 8px 10px;
  border-radius: var(--radius-sm);
  background: var(--accent-soft);
  color: var(--accent-strong);
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
}

/* 分段控件由 global.css 统一提供 */

.base-row {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
  padding: 12px;
  border-radius: var(--radius-control);
  background: var(--glass-2);
  border: 1px solid var(--border);
}

.base-row__field {
  width: 168px;
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

.check {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding-top: 24px;
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
  white-space: nowrap;
  cursor: pointer;
}

.tiers {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
  gap: 12px;
  margin-top: 14px;
}

.tier {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 12px;
  border-radius: var(--radius-control);
  background: var(--glass-2);
  border: 1px solid var(--border);
}

.tier__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.tier__name {
  font-size: var(--fs-body);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-body);
  color: var(--text-strong);
}

.tier__rate {
  display: inline-flex;
  align-items: center;
  height: 20px;
  padding: 0 7px;
  border-radius: 6px;
  background: var(--accent-soft);
  color: var(--accent-strong);
  font-size: var(--fs-caption);
  font-weight: var(--fw-semibold);
  letter-spacing: 0;
}

.tier__hours {
  width: 100%;
}

.tier__calc {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;
}

.tier__unit {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.tier__pay {
  font-size: var(--fs-subhead);
  font-weight: var(--fw-semibold);
  color: var(--text-strong);
}

.tier__hint {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.total {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  margin-top: 14px;
  padding: 14px;
  border-radius: var(--radius-control);
  background: var(--glass-2);
  border: 1px solid var(--border);
}

.total__left {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.total__label {
  font-size: var(--fs-label);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

.total__meta {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.total__amount {
  font-size: 24px;
  font-weight: var(--fw-semibold);
  letter-spacing: -0.02em;
  font-variant-numeric: tabular-nums;
  color: var(--positive);
}

/* —— 同步到收入项 —— */

.sync {
  margin-top: 12px;
  padding: 12px 14px;
  border-radius: var(--radius-control);
  border: 1px solid var(--border);
  background: var(--glass-1);
  transition: var(--transition);
}

.sync.is-on {
  border-color: rgba(10, 132, 255, 0.35);
  background: var(--accent-soft);
}

.sync__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}

.check--strong {
  padding-top: 0;
  color: var(--text-strong);
  font-size: var(--fs-body);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-body);
}

.sync__status {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--accent-strong);
}

.sync__status--off {
  color: var(--text-muted);
}

.sync__status strong {
  font-weight: var(--fw-semibold);
}

.sync__row {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
  margin-top: 10px;
}

.sync__label {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

.sync__select {
  min-width: 150px;
}

.sync__hint {
  margin: 10px 0 0;
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
  color: var(--text-muted);
}

.details {
  margin-top: 14px;
  padding-top: 12px;
  border-top: 1px solid var(--divider);
}

.details summary {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
  cursor: pointer;
  user-select: none;
}

.details summary:hover {
  color: var(--text);
}

.details__grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 14px 16px;
  margin-top: 12px;
}

.disclaimer {
  margin: 14px 0 0;
  padding-top: 12px;
  border-top: 1px solid var(--divider);
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
  color: var(--text-muted);
}
</style>
