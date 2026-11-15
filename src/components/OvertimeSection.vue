<script setup lang="ts">
import { computed, watch } from "vue";
import type { SalaryState } from "../core/defaults";
import { formatMoney, formatRate, round2 } from "../core/money";
import {
  HOLIDAY_RATE,
  WEEKDAY_RATE,
  WEEKEND_RATE,
  calcOvertime,
} from "../core/overtime";
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
 */
const props = defineProps<{ state: SalaryState }>();

/** 加班费的输入对象（直接引用 store，改动即持久化）。 */
const input = computed(() => props.state.overtime);

const basicSalary = computed(() => {
  const basic = props.state.incomes.find((item) => item.label.includes("基本工资"));
  if (basic) return basic.amount;
  return props.state.incomes.find((item) => item.includeInSocialBase)?.amount ?? 0;
});

// 跟随基本工资：收入项里的基本工资一变，基数同步跟上
watch(
  basicSalary,
  (value) => {
    if (input.value.followBasicSalary && input.value.mode === "monthly") {
      input.value.base = value;
    }
  },
  { immediate: true },
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
  if (value) input.value.base = basicSalary.value;
}

/** 记住进入时薪模式前是否跟随基本工资，切回来时才能无损还原。 */
let followBeforeHourly = true;

/** 切换月薪 / 时薪模式：把当前小时工资带过去，避免切完数字归零。 */
function switchMode(mode: "monthly" | "hourly"): void {
  if (input.value.mode === mode) return;
  const currentHourly = result.value.hourlyBase;
  if (mode === "hourly") {
    followBeforeHourly = input.value.followBasicSalary;
    input.value.hourlyRate = currentHourly;
    input.value.followBasicSalary = false;
  } else {
    // 月薪 ÷ 21.75 ÷ 8 的四舍五入再乘回去会有零点几元的误差，
    // 所以原来是跟随基本工资的话直接还原，不用反算。
    if (followBeforeHourly) {
      input.value.followBasicSalary = true;
      input.value.base = basicSalary.value;
    } else {
      // 从时薪折算回月薪：时薪 × 21.75 × 8
      input.value.base = round2(currentHourly * input.value.monthlyDays * input.value.dailyHours);
      input.value.followBasicSalary = false;
    }
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

function resetHours(): void {
  input.value.weekdayHours = 0;
  input.value.weekendHours = 0;
  input.value.holidayHours = 0;
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
    `${formatMoney(input.value.base)} ÷ ${input.value.monthlyDays} ÷ ${input.value.dailyHours} = ${formatMoney(result.value.hourlyBase)} 元/小时`,
);

const isHourly = computed(() => input.value.mode === "hourly");
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
            v-model="input.base"
            :disabled="input.followBasicSalary"
            class="base-row__field"
          />
          <span class="field__hint">
            折算小时工资 = {{ formula }}
          </span>
        </label>

        <label v-else class="field">
          <span class="field__label">加班费基数（元/小时）</span>
          <NumberField v-model="input.hourlyRate" class="base-row__field" suffix="元/时" />
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
            :class="{ active: input.entryMode === 'manual' }"
            @click="input.entryMode = 'manual'"
          >
            直接填合计
          </button>
          <button
            type="button"
            :class="{ active: input.entryMode === 'calendar' }"
            @click="input.entryMode = 'calendar'"
          >
            按日历填写
          </button>
        </div>
      </div>

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
              {{ formatMoney(result[`${tier.key}Rate`]) }} 元/小时
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
  font-size: 12px;
  color: var(--text-muted);
}

.segmented {
  display: inline-flex;
  padding: 2px;
  gap: 2px;
  border-radius: var(--radius-sm);
  background: var(--glass-1);
  border: 1px solid var(--border);
}

.segmented button {
  height: 24px;
  padding: 0 11px;
  border: 0;
  border-radius: 6px;
  background: transparent;
  color: var(--text-muted);
  font-size: 11px;
  font-weight: 500;
  transition: var(--transition);
}

.segmented button:hover {
  color: var(--text-strong);
}

.segmented button.active {
  background: var(--glass-3);
  color: var(--text-strong);
  box-shadow: 0 1px 0 rgba(255, 255, 255, 0.1) inset;
}

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
  font-size: 12px;
  color: var(--text);
  font-weight: 550;
}

.field__hint {
  font-size: 11px;
  color: var(--text-muted);
}

.check {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding-top: 22px;
  font-size: 12px;
  color: var(--text-muted);
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
  font-size: 13px;
  font-weight: 650;
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
  font-size: 11px;
  font-weight: 650;
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
  font-size: 11px;
  color: var(--text-muted);
}

.tier__pay {
  font-size: 14px;
  color: var(--text-strong);
}

.tier__hint {
  font-size: 11px;
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
  font-size: 12px;
  color: var(--text-muted);
}

.total__meta {
  font-size: 11px;
  color: var(--text-muted);
}

.total__amount {
  font-size: 24px;
  font-weight: 700;
  color: var(--positive);
  letter-spacing: -0.01em;
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
  color: var(--text-strong);
  font-size: 13px;
  font-weight: 500;
}

.sync__status {
  font-size: 12px;
  color: var(--accent-strong);
}

.sync__status--off {
  color: var(--text-muted);
}

.sync__status strong {
  font-weight: 600;
}

.sync__row {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
  margin-top: 10px;
}

.sync__label {
  font-size: 12px;
  color: var(--text-muted);
}

.sync__select {
  min-width: 150px;
}

.sync__hint {
  margin: 10px 0 0;
  font-size: 11px;
  line-height: 1.6;
  color: var(--text-muted);
}

.details {
  margin-top: 14px;
  padding-top: 12px;
  border-top: 1px solid var(--divider);
}

.details summary {
  font-size: 12px;
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
  font-size: 11px;
  line-height: 1.6;
  color: var(--text-muted);
}
</style>
