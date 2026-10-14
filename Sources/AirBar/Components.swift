import SwiftUI

/// Front view of the indoor unit with live airflow underneath.
struct ACIllustration: View {
    let isOn: Bool
    let temperature: Int
    let louver: Int

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [.white, Color(white: 0.85)], startPoint: .top, endPoint: .bottom))
                .frame(width: 150, height: 40)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 3) {
                        Text("\(temperature)").font(.system(size: 9, weight: .semibold))
                        Circle().fill(isOn ? Color.green : Color.gray).frame(width: 4, height: 4)
                    }
                    .foregroundStyle(Palette.warm).padding(6)
                    .opacity(isOn ? 1 : 0.4)
                }
                .overlay(alignment: .bottom) {
                    Capsule().fill(Color(white: 0.7)).frame(width: 120, height: 3).padding(.bottom, 6)
                }
            AirflowView(isOn: isOn, louver: louver)
        }
        .padding(.top, 4)
    }
}

/// Louver tilt below horizontal, in degrees, for a vertical-swing position (1 nearly level … 5 pointing down).
func louverAngle(_ level: Double) -> Double { 15 + (level - 1) * 17.5 }

/// Animated air streams under the AC. Their reach and spread follow the louver position;
/// position 0 (auto) sweeps continuously like the real louver.
struct AirflowView: View {
    let isOn: Bool
    let louver: Int

    var body: some View {
        TimelineView(.animation(paused: !isOn)) { context in
            Canvas { graphics, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let level = louver == 0 ? 3 + 2 * sin(t * 0.8) : Double(louver)
                // A steeper louver throws the air further down and spreads it less.
                let reach = size.height * (0.45 + 0.1375 * (level - 1))
                let spread = 0.55 - 0.1 * (level - 1)
                for stream in 0..<9 {
                    let offset = Double(stream) - 4
                    let start = CGPoint(x: size.width / 2 + offset * size.width * 0.075, y: 0)
                    let end = CGPoint(x: start.x + offset * spread * reach * 0.3, y: reach)
                    for dash in 0..<3 {
                        let p = (t * 0.7 + Double(dash) / 3 + Double(stream) * 0.11).truncatingRemainder(dividingBy: 1)
                        let q = min(1, p + 0.16)
                        var path = Path()
                        path.move(to: CGPoint(x: start.x + (end.x - start.x) * p, y: start.y + (end.y - start.y) * p))
                        path.addLine(to: CGPoint(x: start.x + (end.x - start.x) * q, y: start.y + (end.y - start.y) * q))
                        graphics.stroke(path, with: .color(.white.opacity(0.55 * (1 - p))),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
            }
        }
        .frame(height: 40)
        .opacity(isOn ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: isOn)
    }
}

/// Side view of the louver angle for one vertical-swing position.
struct LouverIcon: View {
    let level: Int

    var body: some View {
        Canvas { graphics, size in
            let unit = Path(roundedRect: CGRect(x: 2, y: 2, width: size.width * 0.45, height: 4), cornerRadius: 2)
            graphics.fill(unit, with: .color(.white.opacity(0.5)))
            let angle = louverAngle(Double(level)) * .pi / 180
            let origin = CGPoint(x: size.width * 0.45, y: 5)
            var flow = Path()
            flow.move(to: origin)
            flow.addLine(to: CGPoint(x: origin.x + cos(angle) * size.width * 0.5, y: origin.y + sin(angle) * size.width * 0.5))
            graphics.stroke(flow, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 26, height: 22)
    }
}

/// Vertical louver picker: auto swing or a fixed position L1–L5.
struct LouverPicker: View {
    let current: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            option(0) {
                Image(systemName: "arrow.up.and.down").font(.system(size: 13)).frame(height: 22)
                Text("Swing").font(.system(size: 10, weight: .medium))
            }
            ForEach(1...5, id: \.self) { level in
                option(level) {
                    LouverIcon(level: level)
                    Text("L\(level)").font(.system(size: 10, weight: .medium))
                }
            }
        }
    }

    private func option<Content: View>(_ level: Int, @ViewBuilder content: () -> Content) -> some View {
        Button { select(level) } label: {
            VStack(spacing: 3, content: content)
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(level == current ? Palette.accent : Palette.tile))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A row of capsule buttons for picking one value.
struct OptionChips<Value: Equatable>: View {
    let options: [(String, Value)]
    let current: Value
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { index in
                let (label, value) = options[index]
                Button { select(value) } label: {
                    Text(label).font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(Capsule().fill(value == current ? Palette.accent : Palette.tile))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Slider with a cool-to-warm gradient track. `onCommit` fires when dragging ends.
struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geo in
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = fraction * (geo.size.width - 24)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.tile)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.accent, Palette.warm], startPoint: .leading, endPoint: .trailing))
                    .frame(width: x + 24)
                Circle().fill(.white).frame(width: 20, height: 20).shadow(radius: 2).offset(x: x + 2)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let f = min(1, max(0, (drag.location.x - 12) / (geo.size.width - 24)))
                    value = (range.lowerBound + f * (range.upperBound - range.lowerBound)).rounded()
                }
                .onEnded { _ in onCommit() })
        }
        .frame(height: 24)
    }
}

struct TileLabel: View {
    let title: String
    let value: String
    let icon: String
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Palette.accent)
                .frame(height: 20)
            Text(title).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            Text(value).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(highlighted ? Palette.accent.opacity(0.3) : Palette.tile))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
