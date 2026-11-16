//
//  City.swift
//  各城市社保公积金默认参数，与 shared/cityPolicies.ts 一致。
//
//  这些是**示例默认值**，每年 7 月各地会调整。界面上所有字段都能改。
//

import Foundation

struct City: Identifiable, Hashable {
    let id: String
    let name: String
    let socialBaseMin: Double
    let socialBaseMax: Double
    let housingFundBaseMin: Double
    let housingFundBaseMax: Double
    let pensionRate: Double
    let medicalRate: Double
    let unemploymentRate: Double
    let housingFundRate: Double
    let medicalExtra: Double

    /// 转换成社保配置（基数取上下限下限起步，和 TS 版 socialConfigFromCity 一致）
    var socialConfig: SocialConfig {
        SocialConfig(
            socialBase: socialBaseMin,
            socialBaseMin: socialBaseMin,
            socialBaseMax: socialBaseMax,
            housingFundBase: housingFundBaseMin,
            housingFundBaseMin: housingFundBaseMin,
            housingFundBaseMax: housingFundBaseMax,
            pensionRate: pensionRate,
            medicalRate: medicalRate,
            unemploymentRate: unemploymentRate,
            housingFundRate: housingFundRate,
            medicalExtra: medicalExtra
        )
    }
}

enum CityRepository {
    static let all: [City] = [
        City(
            id: "beijing", name: "北京",
            socialBaseMin: 6821, socialBaseMax: 35811,
            housingFundBaseMin: 2420, housingFundBaseMax: 35811,
            pensionRate: 0.08, medicalRate: 0.02,
            unemploymentRate: 0.005, housingFundRate: 0.12, medicalExtra: 3
        ),
        City(
            id: "shanghai", name: "上海",
            socialBaseMin: 7384, socialBaseMax: 36921,
            housingFundBaseMin: 2690, housingFundBaseMax: 36921,
            pensionRate: 0.08, medicalRate: 0.02,
            unemploymentRate: 0.005, housingFundRate: 0.07, medicalExtra: 0
        ),
        City(
            id: "shenzhen", name: "深圳",
            socialBaseMin: 4492, socialBaseMax: 27501,
            housingFundBaseMin: 2360, housingFundBaseMax: 27501,
            pensionRate: 0.08, medicalRate: 0.02,
            unemploymentRate: 0.003, housingFundRate: 0.05, medicalExtra: 0
        ),
        City(
            id: "guangzhou", name: "广州",
            socialBaseMin: 5500, socialBaseMax: 31182,
            housingFundBaseMin: 2500, housingFundBaseMax: 38568,
            pensionRate: 0.08, medicalRate: 0.02,
            unemploymentRate: 0.002, housingFundRate: 0.05, medicalExtra: 0
        ),
        City(
            id: "hangzhou", name: "杭州",
            socialBaseMin: 4812, socialBaseMax: 24930,
            housingFundBaseMin: 2490, housingFundBaseMax: 24930,
            pensionRate: 0.08, medicalRate: 0.02,
            unemploymentRate: 0.005, housingFundRate: 0.12, medicalExtra: 0
        ),
        City(
            id: "custom", name: "自定义",
            socialBaseMin: 0, socialBaseMax: 40000,
            housingFundBaseMin: 0, housingFundBaseMax: 40000,
            pensionRate: 0.08, medicalRate: 0.02,
            unemploymentRate: 0.005, housingFundRate: 0.12, medicalExtra: 0
        ),
    ]

    static func policy(for id: String) -> City {
        all.first { $0.id == id } ?? all.last!
    }
}
