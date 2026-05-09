import SwiftUI
import Charts

struct UsageSparklineView: View {
    let counts: [Int]
    let color: Color

    var body: some View {
        Chart {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                LineMark(
                    x: .value("Day", index),
                    y: .value("Count", count)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)
            }
            if let last = counts.last, !counts.isEmpty {
                PointMark(
                    x: .value("Day", counts.count - 1),
                    y: .value("Count", last)
                )
                .foregroundStyle(color)
                .symbolSize(28)
            }
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.background(.clear)
        }
    }
}
