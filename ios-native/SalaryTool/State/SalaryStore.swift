//
//  SalaryStore.swift
//  App 状态与持久化。
//
//  和 iOS 版（WebView）的区别：那边主存储写 App 沙盒的 JSON，
//  这里用同样的思路，只是换成 Swift 的 Codable + Documents 目录。
//  文件格式与 Windows 版导出的 JSON 完全一致，可以直接互相导入。
//

import Foundation
import Observation

@MainActor
@Observable
final class SalaryStore {
    // MARK: 状态

    var state: SalaryState {
        didSet {
            scheduleSave()
            // 工时 / 基数一变，联动金额跟着重算
            applyOvertimeToIncome()
        }
    }

    /// 最近一次算出的结果（派生值，不持久化）
    var result: SalaryResult {
        Calculator.compute(state)
    }

    /// 数据完整性提示
    var hints: [String] {
        var list: [String] = []

        if state.socialBaseMode == "auto" {
            let suggested = Calculator.suggestSocialBase(state.incomes)
            if suggested < state.social.socialBaseMin {
                list.append(
                    "社保自动基数 \(Money.format(suggested)) 元低于下限，已按下限 \(Money.formatInteger(state.social.socialBaseMin)) 元缴纳"
                )
            } else if suggested > state.social.socialBaseMax {
                list.append(
                    "社保自动基数 \(Money.format(suggested)) 元高于上限，已按上限 \(Money.formatInteger(state.social.socialBaseMax)) 元缴纳"
                )
            }
        }

        if state.housingFundBaseMode == "auto" {
            let suggested = Calculator.suggestHousingFundBase(state.incomes)
            if suggested < state.social.housingFundBaseMin {
                list.append(
                    "公积金自动基数 \(Money.format(suggested)) 元低于下限，已按下限 \(Money.formatInteger(state.social.housingFundBaseMin)) 元缴纳"
                )
            } else if suggested > state.social.housingFundBaseMax {
                list.append(
                    "公积金自动基数 \(Money.format(suggested)) 元高于上限，已按上限 \(Money.formatInteger(state.social.housingFundBaseMax)) 元缴纳"
                )
            }
        }

        let missing = Calculator.missingMonths(state)
        if !missing.isEmpty {
            list.append("第 \(missing.map(String.init).joined(separator: "、")) 月缺少记录，累计数据会偏小")
        }

        return list
    }

    // MARK: 生命周期

    private var saveTask: Task<Void, Never>?

    init() {
        self.state = Self.load() ?? .sample
    }

    // MARK: - 持久化

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 状态文件的路径（放 Documents，用户能在「文件」App 里看到导出）
    ///
    /// nonisolated：写盘在后台线程做，不能受 @MainActor 限制。
    nonisolated static var stateFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("salarytool-state.json")
    }

    private static func load() -> SalaryState? {
        guard let data = try? Data(contentsOf: Self.stateFileURL) else { return nil }
        return try? JSONDecoder().decode(SalaryState.self, from: data)
    }

    /// 防抖保存：连续修改时只在停手 0.3 秒后写盘一次
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task { [snapshot] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            // 写盘在主线程之外做，避免大文件时卡输入
            await Self.write(snapshot)
        }
    }

    /// 编码 + 原子写。放到后台任务里执行，不阻塞输入。
    private nonisolated static func write(_ state: SalaryState) async {
        let url = stateFileURL
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(state) {
                    // 原子写：先写临时文件再替换，避免中途崩溃留下半个文件
                    try? data.write(to: url, options: .atomic)
                }
                cont.resume()
            }
        }
    }

    /// 立即保存（退出前、导出前调用）
    func saveNow() {
        saveTask?.cancel()
        let snapshot = state
        let url = Self.stateFileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 动作

    func reset() {
        state = .sample
        saveNow()
    }

    func addIncome(label: String, amount: Double = 0) {
        let preset = IncomePreset.all.first { $0.label == label } ?? IncomePreset.basic
        state.incomes.append(
            IncomeItem(
                label: preset.label,
                amount: amount,
                includeInSocialBase: preset.includeInSocialBase,
                includeInHousingFundBase: preset.includeInHousingFundBase,
                taxable: preset.taxable
            )
        )
    }

    func removeIncome(id: String) {
        state.incomes.removeAll { $0.id == id }
    }

    func addDeduction(label: String, amount: Double = 0) {
        let preset = DeductionPreset.all.first { $0.label == label } ?? DeductionPreset.other
        state.deductions.append(
            DeductionItem(label: preset.label, amount: amount, preTax: preset.preTax)
        )
    }

    func removeDeduction(id: String) {
        state.deductions.removeAll { $0.id == id }
    }

    func addMonth() {
        let next = min(12, Int(state.ytd.monthIndex) + 1)
        state.months.append(
            MonthRecord(
                month: Double(next),
                taxableIncome: Money.round2(result.taxableIncome),
                socialDeduction: Money.round2(result.social.total),
                specialDeduction: Money.round2(state.special.total),
                taxPaid: Money.round2(result.taxThisMonth)
            )
        )
    }

    func removeMonth(id: String) {
        state.months.removeAll { $0.id == id }
    }

    // MARK: - 加班费 ↔ 收入项联动

    /// 防止「写回收入项 → 触发 didSet → 再写一次」的递归
    private var syncingOvertime = false

    /// 加班费要写入的收入项；没绑定或绑定项被删时返回 nil。
    ///
    /// 只认名称**完全等于**「加班费」。不用模糊匹配，因为
    /// 加班补贴 / 加班补助是公司另发的固定钱，算出来的是按工时×倍率，
    /// 混在一起会把账算错。
    func findOvertimeIncome() -> IncomeItem? {
        if let id = state.overtimeSync.incomeId,
           let item = state.incomes.first(where: { $0.id == id }) {
            return item
        }
        return state.incomes.first { $0.label.trimmingCharacters(in: .whitespaces) == "加班费" }
    }

    /// 确保有一个可写入的「加班费」收入项：先按 id 找，再按名字找，都没有就新建。
    @discardableResult
    func ensureOvertimeIncome() -> IncomeItem {
        if let existing = findOvertimeIncome() {
            state.overtimeSync.incomeId = existing.id
            return existing
        }
        let item = IncomeItem(
            label: "加班费",
            amount: 0,
            // 加班费一般不并进社保 / 公积金基数，但要计税
            includeInSocialBase: false,
            includeInHousingFundBase: false,
            taxable: true
        )
        state.incomes.append(item)
        state.overtimeSync.incomeId = item.id
        return item
    }

    /// 打开 / 关闭联动。
    /// 关闭时把金额清零，避免留下一个和工时对不上的陈旧数字。
    func setOvertimeSyncEnabled(_ enabled: Bool) {
        state.overtimeSync.enabled = enabled
        if enabled {
            ensureOvertimeIncome()
            applyOvertimeToIncome()
        } else if let target = findOvertimeIncome(),
                  let index = state.incomes.firstIndex(where: { $0.id == target.id }) {
            syncingOvertime = true
            state.incomes[index].amount = 0
            syncingOvertime = false
        }
    }

    /// 把算出的加班费合计写进目标收入项。
    ///
    /// 全程持有 `syncingOvertime`：这个函数自己也会改 `state`，
    /// 而 `state` 的 didSet 又会调回来，不挡住就是无限递归。
    private func applyOvertimeToIncome() {
        guard !syncingOvertime, state.overtimeSync.enabled else { return }
        syncingOvertime = true
        defer { syncingOvertime = false }

        let total = Money.round2(OvertimeMath.totalPay(state.overtime))

        // 绑定项被删了就重建一个
        if findOvertimeIncome() == nil {
            ensureOvertimeIncome()
        }
        guard let target = findOvertimeIncome(),
              let index = state.incomes.firstIndex(where: { $0.id == target.id }) else {
            return
        }
        if state.incomes[index].amount != total {
            state.incomes[index].amount = total
        }
    }

    /// 清零工时：只清当前正在用的录入方式，另一边的数据保留。
    func resetOvertimeHours() {
        if state.overtime.entryMode == "calendar" {
            var calendar = state.overtime.calendar ?? .empty()
            calendar.hours = [:]
            state.overtime.calendar = calendar
        } else {
            state.overtime.weekdayHours = 0
            state.overtime.weekendHours = 0
            state.overtime.holidayHours = 0
        }
    }

    /// 日历改了之后，三档合计跟着更新。
    ///
    /// 桌面版是这个规则（`shared/` 注释里写了原因）：日历是按天记的真实工时，
    /// 拿模糊的合计去反推每一天只能靠猜，一旦写进日历就把记录毁了。
    /// 所以只做「日历 → 合计」这一个方向。
    func syncHoursFromCalendar(entryModeCalendar: Bool) {
        guard entryModeCalendar, let calendar = state.overtime.calendar else { return }
        let hours = OvertimeMath.resolveHours(
            OvertimeInput(
                mode: state.overtime.mode,
                entryMode: "calendar",
                base: state.overtime.base,
                followBasicSalary: state.overtime.followBasicSalary,
                hourlyRate: state.overtime.hourlyRate,
                monthlyDays: state.overtime.monthlyDays,
                dailyHours: state.overtime.dailyHours,
                weekdayHours: 0, weekendHours: 0, holidayHours: 0,
                calendar: calendar
            )
        )
        // 只在日历确实有记录时写回，避免用 0 覆盖掉手填的合计
        if hours.workday + hours.rest + hours.holiday <= 0 { return }
        state.overtime.weekdayHours = hours.workday
        state.overtime.weekendHours = hours.rest
        state.overtime.holidayHours = hours.holiday
    }

    /// 切换到某个城市：只更新上下限与比例，不动已填的基数
    func applyCity(_ id: String) {
        let city = CityRepository.policy(for: id)
        state.cityId = city.id
        state.social.socialBaseMin = city.socialBaseMin
        state.social.socialBaseMax = city.socialBaseMax
        state.social.housingFundBaseMin = city.housingFundBaseMin
        state.social.housingFundBaseMax = city.housingFundBaseMax
        state.social.pensionRate = city.pensionRate
        state.social.medicalRate = city.medicalRate
        state.social.unemploymentRate = city.unemploymentRate
        state.social.housingFundRate = city.housingFundRate
        state.social.medicalExtra = city.medicalExtra
    }

    // MARK: - 导入导出

    /// 导出到 Documents，返回文件名
    func export() throws -> String {
        saveNow()
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let name = "salarytool-backup-\(stamp).json"
        let url = Self.documentsURL.appendingPathComponent(name)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
        return name
    }

    /// 导入 JSON 文本；结构不符时抛错
    func importJSON(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        guard let data = trimmed.data(using: .utf8) else { throw ImportError.invalidJSON }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else {
            throw ImportError.invalidJSON
        }
        guard parsed is [String: Any] else { throw ImportError.notObject }

        do {
            state = try JSONDecoder().decode(SalaryState.self, from: data)
            saveNow()
        } catch {
            throw ImportError.decodeFailed
        }
    }

    enum ImportError: LocalizedError {
        case empty, invalidJSON, notObject, decodeFailed

        var errorDescription: String? {
            switch self {
            case .empty: "配置内容为空"
            case .invalidJSON: "不是合法的 JSON，请检查是否漏了括号或引号"
            case .notObject: "配置格式不对，应该是一个 JSON 对象"
            case .decodeFailed: "配置里的字段无法识别"
            }
        }
    }
}

// MARK: - 预设

struct IncomePreset {
    let label: String
    let includeInSocialBase: Bool
    let includeInHousingFundBase: Bool
    let taxable: Bool

    static let basic = IncomePreset(
        label: "基本工资", includeInSocialBase: true,
        includeInHousingFundBase: true, taxable: true
    )

    static let all: [IncomePreset] = [
        basic,
        .init(label: "岗位工资", includeInSocialBase: true, includeInHousingFundBase: true, taxable: true),
        .init(label: "绩效工资", includeInSocialBase: true, includeInHousingFundBase: false, taxable: true),
        .init(label: "综合补贴", includeInSocialBase: true, includeInHousingFundBase: false, taxable: true),
        .init(label: "租房补贴", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true),
        .init(label: "餐补", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true),
        .init(label: "交通补贴", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true),
        .init(label: "通讯补贴", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true),
        .init(label: "全勤奖", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true),
        .init(label: "加班费", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true),
        .init(label: "加班补助", includeInSocialBase: false, includeInHousingFundBase: false, taxable: true),
        .init(label: "报销（非工资）", includeInSocialBase: false, includeInHousingFundBase: false, taxable: false),
    ]
}

struct DeductionPreset {
    let label: String
    let preTax: Bool

    static let other = DeductionPreset(label: "其他扣款", preTax: false)

    static let all: [DeductionPreset] = [
        .init(label: "企业年金（个人）", preTax: true),
        .init(label: "商业健康险", preTax: true),
        .init(label: "迟到/事假扣款", preTax: false),
        other,
    ]
}
