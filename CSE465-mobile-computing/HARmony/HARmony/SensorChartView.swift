import SwiftUI
import Charts

struct SensorChartView: View {
    let title: String
    let data: [ChartDataPoint]
    let yRange: ClosedRange<Double>
    
    private var dynamicYRange: ClosedRange<Double> {
        let values = data.map { $0.value }
        let currentMin = values.min() ?? yRange.lowerBound
        let currentMax = values.max() ?? yRange.upperBound
        
        // Includes the default range (yRange) and extends to the current data's min/max values.
        return min(yRange.lowerBound, currentMin) ... max(yRange.upperBound, currentMax)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Chart {
                ForEach(data) { point in
                    LineMark(
                        x: .value("Index", Double(point.index)),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(by: .value("Axis", point.axis))
                }
            }
            .chartXAxis(.hidden)
            // Fixed precisely to the last 150 points (approx. 3s) (using Double cast to prevent precision errors)
            .chartXScale(domain: Double((data.last?.index ?? 0) - 150) ... Double(data.last?.index ?? 0))
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic)
            }
            .chartYScale(domain: dynamicYRange)
            .chartForegroundStyleScale([
                "X": Color.red,
                "Y": Color.green,
                "Z": Color.blue
            ])
            .chartLegend(position: .top, alignment: .leading)
            .clipped() // Forcefully clips lines extending outside the graph area
            .frame(height: 120)
            
            Text("Last 3s")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
