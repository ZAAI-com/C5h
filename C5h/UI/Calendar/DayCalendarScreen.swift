import SwiftUI

struct DayCalendarScreen: View {
    let date: Date

    var body: some View {
        PlaceholderScreen(
            title: "Day Calendar",
            systemImage: AppTab.today.systemImage,
            subtitle: "Planned and actual 5-hour windows for \(formatted(date))."
        )
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct WeekCalendarScreen: View {
    var body: some View {
        PlaceholderScreen(
            title: "Week Calendar",
            systemImage: AppTab.calendar.systemImage,
            subtitle: "7-day overview by provider."
        )
    }
}

#Preview {
    DayCalendarScreen(date: .now)
        .frame(width: 1100, height: 700)
}
