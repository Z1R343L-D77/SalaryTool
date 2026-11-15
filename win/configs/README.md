# 配置文件说明

这里的 `.json` 是完整的工资配置，可以在应用里点「导入配置」直接粘贴或选择文件。

## 示例工资（`my-salary.json`）

一份虚构的示例数据，用来演示「手动基数 / 按月累计 / 专项附加扣除中途申报」这些常见情况。
数字与任何真实工资条无关，可以随意改。

对应本月：应付 15,330 → 实发 12,034.98，第 8 个月，本月个税 343.02。

| 字段 | 值 | 说明 |
| --- | --- | --- |
| `cityId` | `hangzhou` | 城市，决定上下限默认值 |
| `socialBaseMode` | `auto` | 社保基数按收入自动推算 |
| `housingFundBaseMode` | `auto` | 公积金基数独立推算，口径可以不同 |
| `social.socialBase` | 14400 | 基本 12000 + 绩效 2400，落在上下限内 |
| `social.housingFundBase` | 12000 | 只有基本工资计入公积金基数 |
| `social.*Rate` | 8% / 2% / 0.5% / 12% | 杭州个人比例 |
| `incomes` | 5 项 | 基本 12000、绩效 2400、餐补 330、交通 400、全勤 200 |
| `special` | 3000 | 子女教育 2000 + 住房贷款利息 1000 |
| `ytdMode` | `records` | 累计数据由按月记录自动累加 |
| `ytd.monthIndex` | 8 | 本次是第 8 个月 |
| `months` | 7 条 | 前七个月：收入 15,330、社保公积金 2,952、已缴个税合计 1,039.38 |

### 专项附加扣除为什么前两个月只有 1,000

1、2 月只申报了住房贷款利息，3 月起才把子女教育加进来：

```text
1 月  1,000
2 月  1,000
3–7 月 各 3,000   →  截至上月累计 17,000
本月   3,000      →  累计 20,000
```

如果直接在配置里把每月专项附加写成 3,000、前几个月不单独记录，累计值会变成 21,000，
个税和到手都会差一截。「按月记录」模式正是为了准确还原这种中途变化。

### 注意

- 按「自动」模式，社保基数取「计入社保基数」的收入合计（基本 + 绩效 = 14,400），
  公积金基数取「计入公积金基数」的合计（只有基本工资 = 12,000）。
  收入项的三个开关只在自动模式下影响基数，手动模式下由 `social.*Base` 决定。
- 累计收入、累计社保、累计专项附加都来自 `months`，只统计 `monthIndex` 之前的月份。
- 每月只需：把月份 +1，然后「+ 添加月份」，用 ⟳ 按钮回填当月数字，再按工资条核对个税。

## 格式说明

```jsonc
{
  "cityId": "hangzhou",          // beijing | shanghai | shenzhen | guangzhou | hangzhou | custom
  "socialBaseMode": "auto",      // auto 按收入自动推算 | manual 手动填写
  "housingFundBaseMode": "auto", // 公积金基数单独设置，可与社保不同
  "incomes": [
    {
      "id": "income-basic",      // 任意唯一字符串
      "label": "基本工资",
      "amount": 12000,
      "includeInSocialBase": true,      // 自动模式下是否计入社保基数
      "includeInHousingFundBase": true, // 自动模式下是否计入公积金基数
      "taxable": true                   // 是否计入个税应纳税所得额
    }
  ],
  "deductions": [],              // 税后/税前其他扣除：{ id, label, amount, preTax }
  "social": {
    "socialBase": 14400,         // 社保缴费基数
    "socialBaseMin": 4812,       // 低于此值按下限缴纳
    "socialBaseMax": 24930,
    "housingFundBase": 12000,    // 公积金基数（可与社保不同）
    "housingFundBaseMin": 2490,
    "housingFundBaseMax": 24930,
    "pensionRate": 0.08,         // 养老个人比例
    "medicalRate": 0.02,
    "unemploymentRate": 0.005,
    "housingFundRate": 0.12,
    "medicalExtra": 0            // 大额医疗互助等固定项
  },
  "special": {                   // 专项附加扣除，全部为「每月」金额
    "childrenEducation": 2000,
    "continuingEducation": 0,
    "seriousIllness": 0,
    "housingLoanInterest": 1000,
    "housingRent": 0,
    "elderlyCare": 0,
    "infantCare": 0
  },
  "ytdMode": "records",          // manual 手填累计 | records 按月记录累加
  "ytd": {                       // 手填模式下使用；records 模式下只有 monthIndex 生效
    "monthIndex": 8,             // 本次是第几个月
    "taxableIncome": 0,
    "socialDeduction": 0,
    "specialDeduction": 0,
    "taxPaid": 0
  },
  "months": [                    // 按月记录，只统计 monthIndex 之前的月份
    {
      "id": "month-1",
      "month": 1,
      "taxableIncome": 15330,     // 该月计税收入
      "socialDeduction": 2952,    // 该月社保公积金个人部分
      "specialDeduction": 1000,   // 该月专项附加扣除
      "taxPaid": 191.34,          // 该月实际被扣的个税
      "note": "子女教育还没申报"
    }
  ],
  "annualBonus": 0,              // 年终奖，本月发放时填
  "bonusTaxMode": "separate"     // separate 单独计税 | combined 并入综合所得
}
```

字段缺失、类型不对、数字写成字符串都能被自动纠正，不用担心报错。未知的 `cityId` 会回落到 `custom`。旧配置没有 `includeInHousingFundBase` 时沿用社保口径，没有 `ytdMode` 时按手填模式处理。
