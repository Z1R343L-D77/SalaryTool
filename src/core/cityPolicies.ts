/**
 * 城市社保公积金的默认参数。
 *
 * 数据仅作为「示例默认值」，每年 7 月各地会公布新的缴费基数上下限和个人比例，
 * 界面上所有字段都允许用户手动覆盖，因此这里不需要保证 100% 精确，
 * 但需要保持结构统一，方便后续新增城市或接入远程配置。
 *
 * 字段含义：
 * - socialBaseMin / socialBaseMax：社保（养老/医疗/失业）缴费基数下限、上限
 * - housingFundBaseMin / housingFundBaseMax：公积金缴费基数上下限
 * - pension / medical / unemployment：个人缴纳比例（0.08 表示 8%）
 * - housingFund：公积金个人缴纳比例默认值（单位和个人一般同比例）
 * - medicalExtra：部分城市的大额医疗互助等固定附加项（元/月），没有则为 0
 */
export interface CitySocialPolicy {
  id: string;
  name: string;
  socialBaseMin: number;
  socialBaseMax: number;
  housingFundBaseMin: number;
  housingFundBaseMax: number;
  pensionRate: number;
  medicalRate: number;
  unemploymentRate: number;
  housingFundRate: number;
  medicalExtra: number;
  note?: string;
}

export const CITY_POLICIES: CitySocialPolicy[] = [
  {
    id: "beijing",
    name: "北京",
    socialBaseMin: 6821,
    socialBaseMax: 35811,
    housingFundBaseMin: 2420,
    housingFundBaseMax: 35811,
    pensionRate: 0.08,
    medicalRate: 0.02,
    unemploymentRate: 0.005,
    housingFundRate: 0.12,
    medicalExtra: 3,
    note: "示例值，请以北京市人社局当年公布为准",
  },
  {
    id: "shanghai",
    name: "上海",
    socialBaseMin: 7384,
    socialBaseMax: 36921,
    housingFundBaseMin: 2690,
    housingFundBaseMax: 36921,
    pensionRate: 0.08,
    medicalRate: 0.02,
    unemploymentRate: 0.005,
    housingFundRate: 0.07,
    medicalExtra: 0,
    note: "示例值，请以上海市人社局当年公布为准",
  },
  {
    id: "shenzhen",
    name: "深圳",
    socialBaseMin: 4492,
    socialBaseMax: 27501,
    housingFundBaseMin: 2360,
    housingFundBaseMax: 27501,
    pensionRate: 0.08,
    medicalRate: 0.02,
    unemploymentRate: 0.003,
    housingFundRate: 0.05,
    medicalExtra: 0,
    note: "示例值，深圳医保分一/二/三档，此处按一档个人比例估算",
  },
  {
    id: "guangzhou",
    name: "广州",
    socialBaseMin: 5500,
    socialBaseMax: 31182,
    housingFundBaseMin: 2500,
    housingFundBaseMax: 38568,
    pensionRate: 0.08,
    medicalRate: 0.02,
    unemploymentRate: 0.002,
    housingFundRate: 0.05,
    medicalExtra: 0,
    note: "示例值，请以广州市人社局当年公布为准",
  },
  {
    id: "hangzhou",
    name: "杭州",
    socialBaseMin: 4812,
    socialBaseMax: 24930,
    housingFundBaseMin: 2490,
    housingFundBaseMax: 24930,
    pensionRate: 0.08,
    medicalRate: 0.02,
    unemploymentRate: 0.005,
    housingFundRate: 0.12,
    medicalExtra: 0,
    note: "示例值，请以杭州市人社局当年公布为准",
  },
  {
    id: "custom",
    name: "自定义",
    socialBaseMin: 0,
    socialBaseMax: 40000,
    housingFundBaseMin: 0,
    housingFundBaseMax: 40000,
    pensionRate: 0.08,
    medicalRate: 0.02,
    unemploymentRate: 0.005,
    housingFundRate: 0.12,
    medicalExtra: 0,
    note: "所有参数均可手动填写",
  },
];

export function findCityPolicy(id: string): CitySocialPolicy {
  return CITY_POLICIES.find((c) => c.id === id) ?? CITY_POLICIES[CITY_POLICIES.length - 1];
}
