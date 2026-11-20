<script setup lang="ts">
import { computed } from "vue";
import { formatMoney, round2 } from "@shared/money";
import type { DayType } from "@shared/calendar";
import { DAY_TYPE_META, MAX_YEAR, MIN_YEAR, defaultDayType } from "@shared/calendar";
import type { MealCalendar, MealCounts, MealRates, MealSlot } from "@shared/mealAllowance";
import {
  MEAL_LABELS,
  MEAL_SLOTS,
  mealAmount,
  resolveMealScene,
} from "@shared/mealAllowance";
import { buildMonth, flattenMonth } from "@shared/calendar";

/**
 * 误餐补贴日历。
 *
 * 和加班日历长得像，但每格填的不是小时数，而是「早 / 中 / 晚」三个开关。
 * 另外多一个「出」标记：标了出差就整套换成出差单价，不再看当天是周几。
 */
const props = defineProps<{
  calendar: MealCalendar;
  rates: MealRates;
}>();

const MONTHS = Array.from({ length: 12 }, (_, i) => i + 1);
const YEARS = Array.from({ length: MAX_YEAR - MIN_YEAR + 1 }, (_, i) => MIN_YEAR + i);

const weeks = computed(() =>
  buildMonth({
    year: props.calendar.year,
    month: props.calendar.month,
    overrides: props.calendar.overrides,
    hours: {},
    today: todayKey(),
  }),
);

const allDays = computed(() => flattenMonth(weeks.value));

const summary = computed(() => {
  let workday = 0;
  let weekend = 0;
  let trip = 0;
  for (const day of allDays.value) {
    const counts = props.calendar.meals[day.key];
    if (!counts) continue;
    const total = counts.breakfast + counts.lunch + counts.dinner;
    if (total <= 0) continue;
    const scene = resolveMealScene(day.type, props.calendar.trips[day.key] === true);
    if (scene === "trip") trip += total;
    else if (scene === "weekend") weekend += total;
    else workday += total;
  }
  return { workday, weekend, trip, total: workday + weekend + trip };
});

function todayKey(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

const canPrev = computed(
  () => !(props.calendar.year === MIN_YEAR && props.calendar.month === 1),
);
const canNext = computed(
  () => !(props.calendar.year === MAX_YEAR && props.calendar.month === 12),
);

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

/** 取某天的餐次，没有就返回空。 */
function countsOf(key: string): MealCounts {
  return props.calendar.meals[key] ?? { breakfast: 0, lunch: 0, dinner: 0 };
}

/** 切换某一餐。已是 1 就清掉，是 0 就设成 1。 */
function toggleMeal(key: string, slot: MealSlot): void {
  const current = countsOf(key);
  const next: MealCounts = { ...current, [slot]: current[slot] > 0 ? 0 : 1 };
  const total = next.breakfast + next.lunch + next.dinner;
  if (total <= 0) {
    delete props.calendar.meals[key];
  } else {
    props.calendar.meals[key] = next;
  }
}

/** 切换出差标记。 */
function toggleTrip(key: string): void {
  if (props.calendar.trips[key]) delete props.calendar.trips[key];
  else props.calendar.trips[key] = true;
}

/** 点档位标签：工作日 → 休息日 → 节假日 → 回到默认 */
function cycleType(key: string, current: DayType, year: number, month: number, day: number): void {
  const order: DayType[] = ["workday", "rest", "holiday"];
  const next = order[(order.indexOf(current) + 1) % order.length];
  if (next === defaultDayType(year, month, day)) delete props.calendar.overrides[key];
  else props.calendar.overrides[key] = next;
}

/** 某天的金额。 */
function dayAmount(key: string, type: DayType): number {
  const counts = props.calendar.meals[key];
  if (!counts) return 0;
  const scene = resolveMealScene(type, props.calendar.trips[key] === true);
  return mealAmount(counts, props.rates[scene]);
}

/** 批量：给本月所有工作日 / 休息日勾上该场景的默认餐次 */
function fillScene(target: "workday" | "weekend"): void {
  for (const day of allDays.value) {
    const isTrip = props.calendar.trips[day.key] === true;
    if (isTrip) continue;
    const scene = day.type === "workday" ? "workday" : "weekend";
    if (scene !== target) continue;
    const rates = props.rates[scene];
    const counts: MealCounts = {
      breakfast: rates.breakfast > 0 ? 1 : 0,
      lunch: rates.lunch > 0 ? 1 : 0,
      dinner: rates.dinner > 0 ? 1 : 0,
    };
    if (counts.breakfast + counts.lunch + counts.dinner > 0) {
      props.calendar.meals[day.key] = counts;
    }
  }
}

function clearMonth(): void {
  // 只清当前显示的月份
  const prefix = `${props.calendar.year}-${String(props.calendar.month).padStart(2, "0")}`;
  for (const key of Object.keys(props.calendar.meals)) {
    if (key.startsWith(prefix)) delete props.calendar.meals[key];
  }
  for (const key of Object.keys(props.calendar.trips)) {
    if (key.startsWith(prefix)) delete props.calendar.trips[key];
  }
  for (const key of Object.keys(props.calendar.overrides)) {
    if (key.startsWith(prefix)) delete props.calendar.overrides[key];
  }
}

const monthTotal = computed(() =>
  round2(allDays.value.reduce((sum, day) => sum + dayAmount(day.key, day.type), 0)),
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
        <button class="btn btn--sm" type="button" @click="fillScene('workday')">填工作日</button>
        <button class="btn btn--sm" type="button" @click="fillScene('weekend')">填休息日</button>
        <button class="btn btn--sm btn--ghost" type="button" @click="clearMonth">清空本月</button>
      </div>
    </div>

    <div class="calendar__grid">
      <div class="calendar__head">
        <span v-for="label in ['一', '二', '三', '四', '五', '六', '日']" :key="label" class="calendar__head-cell">
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
            {
              'day--today': day?.isToday,
              'day--override': day?.overridden,
              'day--trip': day && calendar.trips[day.key],
            },
          ]"
        >
          <template v-if="day">
            <div class="day__top">
              <span class="day__num">{{ day.day }}</span>
              <div class="day__tags">
                <button
                  class="day__type"
                  type="button"
                  :title="`${DAY_TYPE_META[day.type].label}（点击切换档位）`"
                  @click="cycleType(day.key, day.type, day.year, day.month, day.day)"
                >
                  {{ DAY_TYPE_META[day.type].short }}
                </button>
                <button
                  class="day__trip"
                  type="button"
                  :class="{ 'is-on': calendar.trips[day.key] }"
                  title="出差（全天三餐按出差单价）"
                  @click="toggleTrip(day.key)"
                >
                  出
                </button>
              </div>
            </div>

            <div class="day__meals">
              <button
                v-for="slot in MEAL_SLOTS"
                :key="slot"
                class="meal"
                type="button"
                :class="{ 'is-on': countsOf(day.key)[slot] > 0 }"
                :title="`${MEAL_LABELS[slot]}餐`"
                @click="toggleMeal(day.key, slot)"
              >
                {{ MEAL_LABELS[slot] }}
              </button>
            </div>

            <span v-if="dayAmount(day.key, day.type) > 0" class="day__pay num">
              {{ formatMoney(dayAmount(day.key, day.type)) }}
            </span>
          </template>
        </div>
      </div>
    </div>

    <div class="calendar__summary">
      <div class="summary-item">
        <span class="summary-item__label">工作日</span>
        <span class="summary-item__value num">{{ summary.workday }} 餐</span>
      </div>
      <div class="summary-item">
        <span class="summary-item__label">周末 / 节假日</span>
        <span class="summary-item__value num">{{ summary.weekend }} 餐</span>
      </div>
      <div class="summary-item">
        <span class="summary-item__label">出差</span>
        <span class="summary-item__value num">{{ summary.trip }} 餐</span>
      </div>
      <div class="summary-item summary-item--total">
        <span class="summary-item__label">
          {{ calendar.month }} 月合计 · {{ summary.total }} 餐
        </span>
        <span class="summary-item__value summary-item__value--total num">
          ¥{{ formatMoney(monthTotal) }}
        </span>
      </div>
    </div>

    <p class="calendar__note">
      点格子里的「早 / 中 / 晚」勾选当天领到的餐次；点「出」标记出差，当天三餐按出差单价计算。
      工作日加班默认只有晚饭，周末和法定节假日默认午饭 + 晚饭，单价都可以在上面改。
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

.calendar__grid {
  border: 1px solid var(--border);
  border-radius: var(--radius-control);
  overflow: hidden;
  background: var(--glass-1);
}

.calendar__head,
.calendar__week {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
}

.calendar__head {
  background: var(--glass-2);
  border-bottom: 1px solid var(--border);
}

.calendar__head-cell {
  padding: 7px 0;
  text-align: center;
  font-size: var(--fs-caption);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.calendar__week + .calendar__week {
  border-top: 1px solid var(--divider);
}

.day {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-height: 74px;
  padding: 4px;
  border-right: 1px solid var(--divider);
  transition: var(--transition);
}

.day:last-child {
  border-right: 0;
}

.day--empty {
  background: transparent;
}

.day--today {
  box-shadow: inset 0 0 0 1px var(--accent);
  border-radius: 4px;
}

.day--rest {
  background: rgba(255, 159, 10, 0.05);
}

.day--holiday {
  background: rgba(255, 69, 58, 0.06);
}

.day--trip {
  background: rgba(10, 132, 255, 0.09);
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

.day__tags {
  display: flex;
  gap: 1px;
}

.day__type,
.day__trip {
  width: 15px;
  height: 15px;
  padding: 0;
  border: 0;
  border-radius: 3px;
  background: transparent;
  color: var(--text-faint);
  font-size: var(--fs-micro);
  line-height: 1;
  transition: var(--transition);
}

.day__type:hover,
.day__trip:hover {
  background: var(--glass-hover);
  color: var(--text-strong);
}

.day--rest .day__type {
  color: var(--warning);
}

.day--holiday .day__type {
  color: var(--negative);
}

.day__trip.is-on {
  background: var(--accent);
  color: #fff;
}

.day__meals {
  display: flex;
  gap: 3px;
}

.meal {
  flex: 1;
  min-width: 0;
  height: 22px;
  padding: 0;
  border: 1px solid var(--border);
  border-radius: 4px;
  background: transparent;
  color: var(--text-faint);
  font-size: var(--fs-micro);
  line-height: 1;
  transition: var(--transition);
}

.meal:hover {
  border-color: var(--border-strong);
  color: var(--text);
}

.meal.is-on {
  border-color: transparent;
  background: var(--accent-soft);
  color: var(--accent-strong);
  font-weight: var(--fw-semibold);
}

.day__pay {
  margin-top: auto;
  text-align: right;
  font-size: var(--fs-micro);
  color: var(--positive);
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
