// The diagrams tab: every chord the song uses, transposed, drawn once; an unknown chord shows its name alone.
import SwiftUI

struct DiagramsTab: View {
    let chords: [String]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 16) {
                ForEach(chords, id: \.self) { symbol in
                    VStack(spacing: 4) {
                        Text(symbol).font(.headline)
                        if let f = ChordDiagrams.shared.fingering(for: symbol) {
                            ChordDiagramView(fingering: f).frame(width: 90, height: 110)
                        } else {
                            Text("no diagram").font(.caption).foregroundStyle(.secondary).frame(width: 90, height: 110)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

/// One fingering on a Canvas: strings, frets, dots, barres, open and muted marks, the base fret when above the nut.
struct ChordDiagramView: View {
    let fingering: ChordFingering

    var body: some View {
        Canvas { ctx, size in
            let strings = max(fingering.frets.count, 2), frets = 5
            let left = 14.0, top = 16.0, w = size.width - left - 4, h = size.height - top - 4
            let dx = w / Double(strings - 1), dy = h / Double(frets)
            func x(_ s: Int) -> Double { left + Double(s) * dx }
            func y(_ f: Int) -> Double { top + Double(f) * dy }
            let ink = Color.primary
            for s in 0..<strings { ctx.stroke(Path { $0.move(to: CGPoint(x: x(s), y: y(0))); $0.addLine(to: CGPoint(x: x(s), y: y(frets))) }, with: .color(ink.opacity(0.6)), lineWidth: 1) }
            for f in 0...frets {
                let width = f == 0 && fingering.baseFret == 1 ? 3.0 : 1.0
                ctx.stroke(Path { $0.move(to: CGPoint(x: x(0), y: y(f))); $0.addLine(to: CGPoint(x: x(strings - 1), y: y(f))) }, with: .color(ink.opacity(0.6)), lineWidth: width)
            }
            if fingering.baseFret > 1 {
                ctx.draw(Text("\(fingering.baseFret)fr").font(.caption2), at: CGPoint(x: 6, y: y(0) + dy / 2), anchor: .center)
            }
            for barre in fingering.barres {
                let held = fingering.frets.indices.filter { fingering.frets[$0] == barre }
                if let a = held.first, let b = held.last {
                    ctx.fill(Path(roundedRect: CGRect(x: x(a) - 5, y: y(barre - 1) + dy * 0.15, width: x(b) - x(a) + 10, height: dy * 0.7), cornerRadius: 5), with: .color(ink))
                }
            }
            for (s, fret) in fingering.frets.enumerated() {
                if fret > 0 {
                    ctx.fill(Path(ellipseIn: CGRect(x: x(s) - 5, y: y(fret - 1) + dy / 2 - 5, width: 10, height: 10)), with: .color(ink))
                } else {
                    let mark = Path(ellipseIn: CGRect(x: x(s) - 4, y: 3, width: 8, height: 8))
                    if fret == 0 { ctx.stroke(mark, with: .color(ink), lineWidth: 1) } else {
                        ctx.draw(Text("x").font(.caption2), at: CGPoint(x: x(s), y: 7), anchor: .center)
                    }
                }
            }
        }
    }
}
