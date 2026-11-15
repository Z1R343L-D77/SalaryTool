<script setup lang="ts">
import { computed, ref } from "vue";
import type { CalendarDay, DayType } from "../core/calendar";
import {
  DAY_TYPE_META,
  MAX_YEAR,
  MIN_YEAR,
  WEEKDAY_LABELS,
  buildMonth,
  dayKeyOf,
  flattenMonth,
  summarizeMonth,
} from "../core/calendar";
import { formatMoney, formatPrecise } from "../core/money";

/**
 * 加班日历：按天填工时，自动按日期判断工作日 / 休息日 / 法定节假日。
 *
 * 点击日期格子右侧的小标签可以手动改档位（调休上班、非法定节假日放假等），
 * 底部的档位统计会实时汇总到加班费计算。
 */
const props = defineProps<{
  calendar: { year: number; month: number; hours: Record<string, number>; overrides: Record<string, DayType> };
  /** 每小时单价（已含倍率），用于显示每天的折算金额 */
  weekdayRate: number;
  weekendRate: number;
  holidayRate: number;
}>();

const MONTHS = Array.from({ length: 12 }, (_, i) => i + 1);
const YEARS = Array.from({ length: MAX_YEAR - MIN_YEAR + 1 }, (_, i) => MIN_YEAR + i);

const todayKey = dayKeyOf(
  new Date().getFullYear(),
  new Date().getMonth() + 1,
  new Date().getDate(),
);

const weeks = computed(() =>
  buildMonth({
    year: props.calendar.year,
    month: props.calendar.month,
    overrides: props.calendar.overrides,
    hours: props.calendar.hours,
    today: todayKey,
  }),
);

const allDays = computed(() => flattenMonth(weeks.value));
const summary = computed(() => summarizeMonth(allDays.value));

/** 单日金额 = 当日工时 × 该档单价 */
function dayPay(day: CalendarDay): number {
  const rate =
    day.type === "holiday"
      ? props.holidayRate
      : day.type === "rest"
        ? props.weekendRate
        : props.weekdayRate;
  return day.hours * rate;
}

function setHours(day: CalendarDay, value: string): void {
  const parsed = Number.parseFloat(value.replace(/[^\d.]/g, ""));
  const hours = Number.isFinite(parsed) ? Math.max(0, Math.min(24, parsed)) : 0;
  if (hours === 0) {
    delete props.calendar.hours[day.key];
  } else {
    props.calendar.hours[day.key] = Math.round(hours * 100) / 100;
  }
}

/** 点档位标签：工作日 → 休息日 → 节假日 → 回到默认判断。 */
function cycleType(day: CalendarDay): void {
  const order: DayType[] = ["workday", "rest", "holiday"];
  if (!day.overridden) {
    // 第一次点：前进一档
    props.calendar.overrides[day.key] = order[(order.indexOf(day.type) + 1) % 3];
    return;
  }
  const next = order[(order.indexOf(props.calendar.overrides[day.key]) + 1) % 3];
  const nextType = next;
  // 绕回默认值时删掉覆盖
  const defaultWeeks = buildMonth({
    year: props.calendar.year,
    month: props.calendar.month,
    overrides: {},
    hours: {},
  });
  const defaultDay = flattenMonth(defaultWeeks).find((d) => d.key === day.key);
  if (defaultDay && defaultDay.type === nextType) {
    delete props.calendar.overrides[day.key];
  } else {
    props.calendar.overrides[day.key] = nextType;
  }
}

const quickHours = ref(8);

/** 一键填写：整月所有工作日 / 只用工作日填满 */
function fillWorkdays(): void {
  for (const day of allDays.value) {
    if (day.type === "workday") props.calendar.hours[day.key] = quickHours.value;
  }
}

function fillWeekends(): void {
  for (const day of allDays.value) {
    if (day.type === "rest") props.calendar.hours[day.key] = quickHours.value;
  }
}

function clearMonth(): void {
  props.calendar.hours = {};
  props.calendar.overrides = {};
}

/** 上/下一个月，跨年时自动调整年份并夹在允许范围内。 */
function shiftMonth(delta: number): void {
  let year = props.calendar.year;
  let month = props.calendar.month + delta;
  if (month < 1) {
    month = 12;
    year -= 1;
  } else if (month > 12) {
    month = 1;
    year += 1;
  }
  if (year < MIN_YEAR || year > MAX_YEAR) return;
  props.calendar.year = year;
  props.calendar.month = month;
}

const canPrev = computed(
  () => !(props.calendar.year === MIN_YEAR && props.calendar.month === 1),
);
const canNext = computed(
  () => !(props.calendar.year === MAX_YEAR && props.calendar.month === 12),
);

const monthTotalPay = computed(() =>
  allDays.value.reduce((sum, day) => sum + dayPay(day), 0),
);
</script>

<template>
  <div class="calendar">
    <div class="calendar__toolbar">
      <button
        class="btn btn--ghost btn--icon"
        type="button"
        title="上个月"
        :disabled="!canPrev"
        @click="shiftMonth(-1)"
      >
        ‹
      </button>
      <div class="calendar__picker">
        <select v-model.number="calendar.year" class="select select--year" aria-label="年份">
          <option v-for="year in YEARS" :key="year" :value="year">{{ year }} 年</option>
        </select>
        <select v-model.number="calendar.month" class="select select--month" aria-label="月份">
          <option v-for="month in MONTHS" :key="month" :value="month">{{ month }} 月</option>
        </select>
      </div>
      <button
        class="btn btn--ghost btn--icon"
        type="button"
        title="下个月"
        :disabled="!canNext"
        @click="shiftMonth(1)"
      >
        ›
      </button>

      <div class="calendar__quick">
        <span class="calendar__quick-label">每天</span>
        <input
          v-model.number="quickHours"
          class="calendar__quick-input"
          type="number"
          min="0"
          max="24"
          step="0.5"
          aria-label="批量填写的小时数"
        />
        <span class="calendar__quick-label">小时</span>
        <button class="btn btn--sm" type="button" @click="fillWorkdays">填工作日</button>
        <button class="btn btn--sm" type="button" @click="fillWeekends">填休息日</button>
        <button class="btn btn--sm btn--ghost" type="button" @click="clearMonth">清空本月</button>
      </div>
    </div>

    <div class="calendar__grid">
      <div class="calendar__head">
        <span v-for="label in WEEKDAY_LABELS" :key="label" class="calendar__head-cell">
          周{{ label }}
        </span>
      </div>

      <div v-for="(week, wi) in weeks" :key="wi" class="calendar__week">
        <div
          v-for="(day, di) in week"
          :key="day?.key ?? `empty-${wi}-${di}`"
          class="day"
          :class="[
            day ? `day--${day.type}` : 'day--empty',
            { 'day--today': day?.isToday, 'day--override': day?.overridden },
          ]"
        >
          <template v-if="day">
            <div class="day__top">
              <span class="day__num">{{ day.day }}</span>
              <button
                class="day__type"
                type="button"
                :title="`${DAY_TYPE_META[day.type].label}（点击切换档位）`"
                @click="cycleType(day)"
              >
                {{ DAY_TYPE_META[day.type].short }}
              </button>
            </div>
            <input
              class="day__hours"
              type="text"
              inputmode="decimal"
              :value="day.hours > 0 ? String(day.hours) : ''"
              placeholder="工时"
              :aria-label="`${calendar.month} 月 ${day.day} 日加班小时数`"
              @input="setHours(day, ($event.target as HTMLInputElement).value)"
            />
            <span v-if="day.hours > 0" class="day__pay num">{{ formatMoney(dayPay(day)) }}</span>
          </template>
        </div>
      </div>
    </div>

    <div class="calendar__summary">
      <div class="summary-item summary-item--workday">
        <span class="summary-item__label">工作日 {{ formatPrecise(weekdayRate) }}/h</span>
        <span class="summary-item__value num">{{ summary.workdayHours }} 小时</span>
      </div>
      <div class="summary-item summary-item--rest">
        <span class="summary-item__label">休息日 {{ formatPrecise(weekendRate) }}/h</span>
        <span class="summary-item__value num">{{ summary.restHours }} 小时</span>
      </div>
      <div class="summary-item summary-item--holiday">
        <span class="summary-item__label">节假日 {{ formatPrecise(holidayRate) }}/h</span>
        <span class="summary-item__value num">{{ summary.holidayHours }} 小时</span>
      </div>
      <div class="summary-item summary-item--total">
        <span class="summary-item__label">
          {{ calendar.month }} 月合计 · {{ summary.workedDays }} 天 · {{ summary.totalHours }} 小时
        </span>
        <span class="summary-item__value summary-item__value--total num">
          ¥{{ formatMoney(monthTotalPay) }}
        </span>
      </div>
    </div>

    <p class="calendar__note">
      工作日 1.5 倍、周末 2 倍、法定节假日 3 倍。元旦、劳动节、国庆可自动识别；
      春节 / 清明 / 端午 / 中秋按农历，日期每年不同，需点日期右上角的档位标签手动设为「假」。
      调休上班也点标签改成「班」。
    </p>
  </div>
</template>

<style scoped>
.calendar {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.calendar__toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.calendar__picker {
  display: flex;
  gap: 6px;
}

.select--year {
  min-width: 92px;
}

.select--month {
  min-width: 72px;
}

.calendar__quick {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-left: auto;
  flex-wrap: wrap;
}

.calendar__quick-label {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.calendar__quick-input {
  width: 58px;
  height: 26px;
  padding: 0 6px;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--glass-2);
  color: var(--text-strong);
  font-family: inherit;
  font-size: var(--fs-label);
  font-variant-numeric: tabular-nums;
  text-align: right;
  outline: 0;
}

.calendar__quick-input:focus {
  border-color: var(--accent);
}

.calendar__grid {
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  overflow: hidden;
  background: var(--glass-1);
}

.calendar__head {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  border-bottom: 1px solid var(--divider);
}

.calendar__head-cell {
  padding: 7px 0;
  text-align: center;
  font-size: var(--fs-caption);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.calendar__week {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
}

.calendar__week + .calendar__week {
  border-top: 1px solid var(--divider);
}

.day {
  min-height: 62px;
  padding: 4px 5px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  border-left: 1px solid var(--divider);
  transition: var(--transition);
}

.day:first-child {
  border-left: 0;
}

.day--empty {
  background: transparent;
}

.day--workday {
  background: transparent;
}

.day--rest {
  background: var(--tint-faint);
}

.day--holiday {
  background: rgba(255, 69, 58, 0.08);
}

.day--today {
  box-shadow: inset 0 0 0 1px var(--accent);
}

.day--override .day__type {
  background: var(--accent-soft);
  color: var(--accent-strong);
}

.day__top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 2px;
}

.day__num {
  font-size: var(--fs-micro);
  font-weight: var(--fw-medium);
  font-variant-numeric: tabular-nums;
  color: var(--text-muted);
}

.day__type {
  width: 16px;
  height: 15px;
  padding: 0;
  border: 0;
  border-radius: 4px;
  background: transparent;
  color: var(--text-faint);
  font-size: var(--fs-micro);
  line-height: 1;
  transition: var(--transition);
}

.day__type:hover {
  background: var(--glass-hover);
  color: var(--text-strong);
}

.day--rest .day__type {
  color: var(--warning);
}

.day--holiday .day__type {
  color: var(--negative);
}

.day__hours {
  width: 100%;
  height: 21px;
  padding: 0 4px;
  border: 1px solid transparent;
  border-radius: 4px;
  background: transparent;
  color: var(--text-strong);
  font-family: inherit;
  font-size: var(--fs-micro);
  font-variant-numeric: tabular-nums;
  text-align: right;
  outline: 0;
  transition: var(--transition);
}

/*
 * 空格子的占位符只在悬停时出现。
 * 31 个格子各挂一个「工时」二字，整块日历会显得像一张未填的表单；
 * 需要提示的地方用顶部的批量按钮和下方说明已经讲清楚了。
 */
.day__hours::placeholder {
  color: transparent;
  text-align: left;
}

.day:hover .day__hours::placeholder {
  color: var(--text-faint);
}

.day__hours:hover {
  background: var(--glass-2);
}

.day__hours:focus {
  background: var(--glass-3);
  border-color: var(--accent);
}

.day__hours:focus::placeholder {
  color: var(--text-faint);
}

.day__pay {
  font-size: var(--fs-micro);
  font-variant-numeric: tabular-nums;
  color: var(--positive);
  text-align: right;
  line-height: 1.1;
}

.calendar__summary {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 8px;
}

.summary-item {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 8px 10px;
  border-radius: var(--radius-sm);
  border: 1px solid var(--border);
  background: var(--glass-1);
}

.summary-item__label {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.summary-item__value {
  font-size: var(--fs-body);
  font-weight: var(--fw-medium);
  color: var(--text-strong);
}

.summary-item--workday {
  border-left: 2px solid var(--border-strong);
}
.summary-item--rest {
  border-left: 2px solid var(--warning);
}
.summary-item--holiday {
  border-left: 2px solid var(--negative);
}
.summary-item--total {
  border-left: 2px solid var(--positive);
}

.summary-item__value--total {
  font-size: 17px;
  font-weight: var(--fw-semibold);
  letter-spacing: -0.015em;
  color: var(--positive);
}

.calendar__note {
  margin: 0;
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  line-height: var(--lh-body);
  color: var(--text-faint);
}

@media (max-width: 1080px) {
  .calendar__summary {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
</style>
