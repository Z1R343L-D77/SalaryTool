<script setup lang="ts">
import { computed } from "vue";
import type { SalaryState } from "@shared/defaults";
import { formatMoney } from "@shared/money";
import type { MealScene, MealSlot } from "@shared/mealAllowance";
import {
  MEAL_LABELS,
  MEAL_SCENES,
  MEAL_SCENE_LABELS,
  MEAL_SLOTS,
  calcMealAllowance,
  emptyMealCounts,
  mealAmount,
  mealCountTotal,
  suggestMealsFromOvertime,
} from "@shared/mealAllowance";
import {
  ensureMealIncome,
  findMealIncome,
  setMealSyncEnabled,
} from "../store/useSalaryState";
import NumberField from "./NumberField.vue";
import MealCalendar from "./MealCalendar.vue";

/**
 * 加班误餐补贴。
 *
 * 和加班费是两条独立的线：
 * - 加班费按「工时 × 倍率」算，受劳动法约束
 * - 误餐补贴按「天数 × 餐次 × 单价」算，纯粹是公司制度
 *
 * 所以这里没有基数、没有倍率，只有一张单价表和一台按天记录的小日历。
 * 单价随时可改，改完所有已记录的餐次立刻按新单价重算。
 */
const props = defineProps<{ state: SalaryState }>();

const input = computed(() => props.state.mealAllowance);
const result = computed(() => calcMealAllowance(input.value));
const isCalendar = computed(() => input.value.entryMode === "calendar");

/** 打开联动时绑定到的收入项 */
const boundIncome = computed(() => findMealIncome());
const syncEnabled = computed(() => props.state.mealSync.enabled);

/** 从加班记录补餐次：把加班日历里有工时的那几天勾上默认餐次。 */
const overtimeHoursTotal = computed(() =>
  Object.values(props.state.overtime.calendar.hours).reduce((sum, v) => sum + v, 0),
);

function suggestFromOvertime(): void {
  const suggested = suggestMealsFromOvertime(
    props.state.overtime.calendar,
    input.value.calendar,
  );
  input.value.calendar.meals = suggested;
}

/** 清零：只清当前模式，另一边保留（和加班费的行为一致）。 */
function resetMeals(): void {
  if (isCalendar.value) {
    input.value.calendar.meals = {};
    input.value.calendar.trips = {};
  } else {
    input.value.manual.workday = emptyMealCounts();
    input.value.manual.weekend = emptyMealCounts();
    input.value.manual.trip = emptyMealCounts();
  }
}

function onToggleSync(event: Event): void {
  setMealSyncEnabled((event.target as HTMLInputElement).checked);
}

function onCreateTarget(): void {
  ensureMealIncome();
}

/** 某一档某顿饭对应的单价字段，双向绑定用 */
function rateModel(scene: MealScene, slot: MealSlot) {
  return computed({
    get: () => input.value.rates[scene][slot],
    set: (value: number) => {
      input.value.rates[scene][slot] = value;
    },
  });
}

function manualModel(scene: MealScene, slot: MealSlot) {
  return computed({
    get: () => input.value.manual[scene][slot],
    set: (value: number) => {
      input.value.manual[scene][slot] = value;
    },
  });
}

const manualRows = MEAL_SCENES.map((scene) => ({
  scene,
  cells: MEAL_SLOTS.map((slot) => ({ slot, model: manualModel(scene, slot) })),
  amount: computed(() => mealAmount(input.value.manual[scene], input.value.rates[scene])),
  meals: computed(() => mealCountTotal(input.value.manual[scene])),
}));

function sceneMeals(scene: MealScene): number {
  return scene === "workday" ? result.value.workdayMeals
    : scene === "weekend" ? result.value.weekendMeals
    : result.value.tripMeals;
}

/** 日历模式下每一档的金额，用于底部汇总 */
const calendarBreakdown = computed(() => [
  { scene: "workday" as MealScene, amount: result.value.workday, meals: result.value.workdayMeals },
  { scene: "weekend" as MealScene, amount: result.value.weekend, meals: result.value.weekendMeals },
  { scene: "trip" as MealScene, amount: result.value.trip, meals: result.value.tripMeals },
]);
</script>

<template>
  <section class="card">
    <header class="card__header">
      <h2 class="card__title">
        加班误餐补贴
        <span class="card__subtitle">按天记录，工作日 / 周末 / 出差三套单价</span>
      </h2>
      <span class="total">合计 <strong class="num">{{ formatMoney(result.total) }}</strong> 元</span>
    </header>

    <div class="card__body">
      <!-- 录入方式 -->
      <div class="mode-row">
        <span class="mode-row__label">录入方式</span>
        <div class="segmented" role="radiogroup" aria-label="录入方式">
          <button
            type="button"
            :class="{ active: !isCalendar }"
            @click="input.entryMode = 'manual'"
          >
            直接填餐次
          </button>
          <button
            type="button"
            :class="{ active: isCalendar }"
            @click="input.entryMode = 'calendar'"
          >
            按日历填写
          </button>
        </div>
      </div>

      <!-- 单价表 -->
      <div class="rate-block">
        <div class="rate-block__head">
          <span class="rate-block__title">单价（元/餐）</span>
          <span class="rate-block__hint">改单价后，所有记录立刻按新价重算</span>
        </div>

        <div class="rate-table">
          <div class="rate-table__head">
            <span />
            <span v-for="slot in MEAL_SLOTS" :key="slot" class="rate-table__cell">
              {{ MEAL_LABELS[slot] }}
            </span>
          </div>
          <div v-for="row in MEAL_SCENES" :key="row" class="rate-table__row">
            <span class="rate-table__label">{{ MEAL_SCENE_LABELS[row] }}</span>
            <NumberField
              v-for="slot in MEAL_SLOTS"
              :key="slot"
              v-model="rateModel(row, slot).value"
              :max="200"
              class="rate-table__input"
            />
          </div>
        </div>
      </div>

      <!-- 手填模式 -->
      <template v-if="!isCalendar">
        <div class="manual-block">
          <div class="manual-table">
            <div class="manual-table__head">
              <span>场景</span>
              <span v-for="slot in MEAL_SLOTS" :key="slot" class="manual-table__cell">
                {{ MEAL_LABELS[slot] }}
              </span>
              <span class="manual-table__amount">金额</span>
            </div>
            <div
              v-for="row in manualRows"
              :key="row.scene"
              class="manual-table__row"
            >
              <span class="manual-table__label">{{ MEAL_SCENE_LABELS[row.scene] }}</span>
              <NumberField
                v-for="cell in row.cells"
                :key="cell.slot"
                v-model="cell.model.value"
                :max="31"
                suffix="餐"
                class="manual-table__input"
              />
              <strong class="manual-table__amount num">{{ formatMoney(row.amount.value) }}</strong>
            </div>
          </div>
        </div>
      </template>

      <!-- 日历模式 -->
      <template v-else>
        <div class="calendar-actions">
          <button
            class="btn btn--sm"
            type="button"
            :disabled="overtimeHoursTotal <= 0"
            :title="overtimeHoursTotal > 0
              ? '按加班日历里的工时自动勾选：工作日给晚饭，周末给午饭+晚饭'
              : '加班日历里还没有工时记录'"
            @click="suggestFromOvertime"
          >
            按加班记录补餐次
          </button>
        </div>

        <MealCalendar :calendar="input.calendar" :rates="input.rates" />

        <div class="calendar-summary">
          <div
            v-for="item in calendarBreakdown"
            :key="item.scene"
            class="calendar-summary__cell"
          >
            <span class="calendar-summary__label">{{ MEAL_SCENE_LABELS[item.scene] }}</span>
            <span class="calendar-summary__value num">{{ formatMoney(item.amount) }}</span>
            <span class="calendar-summary__meta">{{ item.meals }} 餐</span>
          </div>
        </div>
      </template>

      <!-- 合计 -->
      <div class="total-block">
        <div class="total-block__left">
          <span class="total-block__label">误餐补贴合计</span>
          <span class="total-block__meta">
            {{ result.totalMeals }} 餐 · 工作日 {{ sceneMeals("workday") }} 餐 ·
            周末 {{ sceneMeals("weekend") }} 餐 · 出差 {{ sceneMeals("trip") }} 餐
          </span>
        </div>
        <strong class="total-block__amount num">¥{{ formatMoney(result.total) }}</strong>
      </div>

      <!-- 同步到收入项 -->
      <div class="sync" :class="{ 'is-on': syncEnabled }">
        <div class="sync__head">
          <label class="check check--strong">
            <input type="checkbox" :checked="syncEnabled" @change="onToggleSync" />
            <span>同步到收入项</span>
          </label>

          <span v-if="syncEnabled" class="sync__status">
            已写入「{{ boundIncome?.label ?? "误餐补贴" }}」
            <strong class="num">{{ formatMoney(boundIncome?.amount ?? 0) }}</strong> 元
          </span>
          <span v-else class="sync__status sync__status--off">
            关闭时只计算，不改动工资单
          </span>

          <button class="btn btn--sm btn--ghost reset" type="button" @click="resetMeals">
            清零餐次
          </button>
        </div>

        <div v-if="syncEnabled && !boundIncome" class="sync__row">
          <button class="btn btn--sm" type="button" @click="onCreateTarget">
            新建「误餐补贴」项
          </button>
        </div>
      </div>

      <p class="disclaimer">
        误餐补贴属于公司自主福利，没有法定标准，单价按实际制度填写。
        作为收入项计税，但通常不计入社保 / 公积金基数。
      </p>
    </div>
  </section>
</template>

<style scoped>
.total {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
  white-space: nowrap;
}

.total strong {
  color: var(--positive);
  font-size: var(--fs-subhead);
  font-weight: var(--fw-semibold);
}

.mode-row {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 14px;
}

.mode-row__label {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

/* —— 单价表 —— */

.rate-block {
  padding: 12px;
  border-radius: var(--radius-control);
  background: var(--glass-2);
  border: 1px solid var(--border);
  margin-bottom: 14px;
}

.rate-block__head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 10px;
  flex-wrap: wrap;
}

.rate-block__title {
  font-size: var(--fs-label);
  font-weight: var(--fw-semibold);
  letter-spacing: var(--ls-label);
  color: var(--text-strong);
}

.rate-block__hint {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-faint);
}

.rate-table {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.rate-table__head,
.rate-table__row {
  display: grid;
  grid-template-columns: 96px repeat(3, minmax(0, 1fr));
  gap: 8px;
  align-items: center;
}

.rate-table__head .rate-table__cell {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
  text-align: center;
}

.rate-table__label {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text);
}

/* —— 手填表 —— */

.manual-block {
  margin-bottom: 14px;
}

.manual-table {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.manual-table__head,
.manual-table__row {
  display: grid;
  grid-template-columns: 96px repeat(3, minmax(0, 1fr)) 84px;
  gap: 8px;
  align-items: center;
}

.manual-table__head span {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.manual-table__head .manual-table__cell {
  text-align: center;
}

.manual-table__head .manual-table__amount {
  text-align: right;
}

.manual-table__label {
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  color: var(--text);
}

.manual-table__amount {
  text-align: right;
  font-size: var(--fs-body);
  font-weight: var(--fw-semibold);
  color: var(--text-strong);
}

/* —— 日历 —— */

.calendar-actions {
  display: flex;
  justify-content: flex-end;
  margin-bottom: 10px;
}

.calendar-summary {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
  margin-top: 12px;
}

.calendar-summary__cell {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 10px 12px;
  border-radius: var(--radius-sm);
  background: var(--glass-2);
  border: 1px solid var(--border);
}

.calendar-summary__label {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.calendar-summary__value {
  font-size: var(--fs-heading);
  font-weight: var(--fw-semibold);
  color: var(--text-strong);
}

.calendar-summary__meta {
  font-size: var(--fs-micro);
  letter-spacing: var(--ls-micro);
  color: var(--text-faint);
}

/* —— 合计 —— */

.total-block {
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

.total-block__left {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.total-block__label {
  font-size: var(--fs-label);
  font-weight: var(--fw-medium);
  letter-spacing: var(--ls-label);
  color: var(--text-muted);
}

.total-block__meta {
  font-size: var(--fs-caption);
  letter-spacing: var(--ls-caption);
  color: var(--text-muted);
}

.total-block__amount {
  font-size: 24px;
  font-weight: var(--fw-semibold);
  letter-spacing: -0.02em;
  color: var(--positive);
}

/* —— 同步 —— */

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
  gap: 12px;
  flex-wrap: wrap;
}

.check {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--text-muted);
  font-size: var(--fs-label);
  letter-spacing: var(--ls-label);
  white-space: nowrap;
  cursor: pointer;
}

.check--strong {
  color: var(--text-strong);
  font-size: var(--fs-body);
  font-weight: var(--fw-medium);
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
  margin-top: 10px;
}

.reset {
  margin-left: auto;
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

@media (max-width: 900px) {
  .rate-table__head,
  .rate-table__row {
    grid-template-columns: 80px repeat(3, minmax(0, 1fr));
  }

  .manual-table__head,
  .manual-table__row {
    grid-template-columns: 80px repeat(3, minmax(0, 1fr)) 72px;
  }
}
</style>
