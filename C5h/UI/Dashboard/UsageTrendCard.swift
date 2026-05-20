import SwiftUI
import C5hCore

struct UsageTrendCard: View {
    let history: [DailyProviderUsage]

    var body: some View {
        DashboardCard(title: "Usage trend (last 7 days)") {
            if history.isEmpty {
                Text("No window data yet.")
                    .foregroundStyle(C5hColors.fgSecondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                UsageAreaChartView(history: history)
                    .frame(minHeight: 160)
            }
        }
    }
}
