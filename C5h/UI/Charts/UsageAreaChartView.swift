import SwiftUI
import Charts
import C5hCore

struct DailyProviderUsage: Identifiable, Sendable, Hashable {
    let date: Date
    let providerID: ProviderID
    let count: Int

    var id: String { "\(providerID.rawValue)-\(date.timeIntervalSince1970)" }
}

struct UsageAreaChartView: View {
    let history: [DailyProviderUsage]

    var body: some View {
        Chart(history) { day in
            BarMark(
                x: .value("Date", day.date, unit: .day),
                y: .value("Windows", day.count)
            )
            .foregroundStyle(by: .value("Provider", day.providerID.displayName))
            .position(by: .value("Provider", day.providerID.displayName))
        }
        .chartForegroundStyleScale([
            ProviderID.claude.displayName: C5hColors.claudeOnGlass,
            ProviderID.codex.displayName: C5hColors.codexOnGlass
        ])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(position: .top, alignment: .leading)
    }
}
