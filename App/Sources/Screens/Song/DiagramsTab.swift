// The diagrams tab: every chord the song uses, transposed, drawn once; an unknown chord shows its name alone.
import SwiftUI

struct DiagramsTab: View {
    let chords: [String]
    @ScaledMetric private var cell = 104.0
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let metrics = Metrics(sizeClass)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: max(148, cell + 40)), spacing: 12)], spacing: 12) {
                ForEach(chords, id: \.self) { symbol in
                    VStack(spacing: 6) {
                        Text(symbol).font(.system(size: 17, weight: .bold))
                        if let f = ChordDiagrams.shared.fingering(for: symbol) {
                            ChordDiagramView(fingering: f).frame(width: cell, height: cell * 7 / 6)
                        } else {
                            Text("no diagram").font(.caption).foregroundStyle(k7.textSecondary).frame(width: cell, height: cell * 7 / 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14).padding(.bottom, 10)
                    .card(radius: 20)
                }
            }
            .padding(.horizontal, metrics.margin).padding(.vertical, 6)
        }
    }
}

/// One fingering on a Canvas: strings, frets, dots, barres, open and muted marks, the base fret when above the nut.
struct ChordDiagramView: View {
    let fingering: ChordFingering

    var body: some View {
        Canvas { ctx, size in
            let strings = max(fingering.frets.count, 2), frets = 5
            let left = 14.0, top = 22.0, w = size.width - left - 14, h = size.height - top - 8
            let dx = w / Double(strings - 1), dy = h / Double(frets), r = 6.5
            func x(_ s: Int) -> Double { left + Double(s) * dx }
            func y(_ f: Int) -> Double { top + Double(f) * dy }
            func line(_ a: CGPoint, _ b: CGPoint, _ opacity: Double, _ width: Double) {
                ctx.stroke(Path { $0.move(to: a); $0.addLine(to: b) }, with: .color(k7.text.opacity(opacity)), lineWidth: width)
            }
            for s in 0..<strings { line(CGPoint(x: x(s), y: y(0)), CGPoint(x: x(s), y: y(frets)), 0.35, 1) }
            for f in 0...frets {
                let nut = f == 0 && fingering.baseFret == 1
                line(CGPoint(x: x(0), y: y(f)), CGPoint(x: x(strings - 1), y: y(f)), nut ? 0.9 : 0.35, nut ? 3 : 1)
            }
            if fingering.baseFret > 1 {
                ctx.draw(Text("\(fingering.baseFret)fr").font(.caption2).foregroundStyle(k7.textSecondary), at: CGPoint(x: 2, y: y(0) + dy / 2), anchor: .leading)
            }
            for barre in fingering.barres {
                let held = fingering.frets.indices.filter { fingering.frets[$0] == barre }
                if let a = held.first, let b = held.last {
                    let mid = y(barre - 1) + dy / 2
                    ctx.fill(Path(roundedRect: CGRect(x: x(a) - r, y: mid - r, width: x(b) - x(a) + 2 * r, height: 2 * r), cornerRadius: r), with: .color(k7.accentSoft))
                }
            }
            for (s, fret) in fingering.frets.enumerated() {
                if fret > 0 {
                    let mid = y(fret - 1) + dy / 2
                    ctx.fill(Path(ellipseIn: CGRect(x: x(s) - r, y: mid - r, width: 2 * r, height: 2 * r)), with: .color(k7.accentSoft))
                } else if fret == 0 {
                    ctx.stroke(Path(ellipseIn: CGRect(x: x(s) - 4, y: 7, width: 8, height: 8)), with: .color(k7.textSecondary), lineWidth: 1.6)
                } else {
                    var cross = Path()
                    cross.move(to: CGPoint(x: x(s) - 3.5, y: 7.5)); cross.addLine(to: CGPoint(x: x(s) + 3.5, y: 14.5))
                    cross.move(to: CGPoint(x: x(s) + 3.5, y: 7.5)); cross.addLine(to: CGPoint(x: x(s) - 3.5, y: 14.5))
                    ctx.stroke(cross, with: .color(k7.textSecondary), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
        }
    }
}
