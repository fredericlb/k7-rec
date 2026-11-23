// Chord diagrams: the column beside the chords on iPad and the Mac, the card a chord opens on iPhone, each under
// the guitar/piano switch; a guitar fingering or a piano's keys drawn on a Canvas. An unknown chord shows its name alone.
import RehearsalText
import SwiftUI

/// Guitar or piano, over the diagrams; the reader's choice, kept for every song.
struct InstrumentSwitch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Picker("Instrument", selection: $prefs.instrument) {
            ForEach(Instrument.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("instrument")
    }
}

/// Every chord the song uses, transposed, drawn once, in a column at the right of the chords.
struct DiagramColumn: View {
    let chords: [String]

    var body: some View {
        ScrollView {
            VStack(spacing: K7Space.s12) {
                InstrumentSwitch()
                ForEach(chords, id: \.self) { DiagramCard(symbol: $0, cell: 84).frame(maxWidth: .infinity).card(radius: 20) }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chord diagrams")
    }
}

/// A chord's name over its diagram, for the instrument the reader chose.
struct DiagramCard: View {
    @Environment(AppModel.self) private var model
    let symbol: String
    let cell: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            Text(symbol).font(.system(size: 17, weight: .bold))
            if model.prefs.instrument == .piano, let v = PianoChord.voicing(symbol) {
                PianoChordView(voicing: v).frame(width: cell * 1.65, height: cell * 0.8).accessibilityHidden(true)
            } else if model.prefs.instrument == .piano {
                Text("no diagram").font(.caption).foregroundStyle(k7.textSecondary).frame(width: cell * 1.65, height: cell * 0.8)
            } else if let f = ChordDiagrams.shared.fingering(for: symbol) {
                ChordDiagramView(fingering: f).frame(width: cell, height: cell * 7 / 6).accessibilityHidden(true)
            } else {
                Text("no diagram").font(.caption).foregroundStyle(k7.textSecondary).frame(width: cell, height: cell * 7 / 6)
            }
        }
        .padding(.top, 14).padding(.bottom, 10).padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
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

/// A piano chord: the keys from a white key below the lowest to one above the highest, the right hand's keys lit
/// with their fingers under them, the left hand's bass paler and marked L.
struct PianoChordView: View {
    let voicing: PianoVoicing
    private static let blacks: Set<Int> = [1, 3, 6, 8, 10]
    private static func black(_ k: Int) -> Bool { blacks.contains(((k % 12) + 12) % 12) }

    var body: some View {
        Canvas { ctx, size in
            let all = voicing.keys + (voicing.bass.map { [$0] } ?? [])
            var lo = all.min()! - 1, hi = all.max()! + 1
            while Self.black(lo) { lo -= 1 }
            while Self.black(hi) { hi += 1 }
            let whites = (lo...hi).filter { !Self.black($0) }
            let label = 16.0, h = size.height - label, ww = size.width / Double(whites.count)
            let bw = ww * 0.62, bh = h * 0.6
            func x(_ k: Int) -> Double {
                Self.black(k) ? Double(whites.firstIndex(of: k + 1)!) * ww - bw / 2 : Double(whites.firstIndex(of: k)!) * ww
            }
            func fill(_ k: Int) -> Color? {
                if voicing.keys.contains(k) { return k7.accentIcon }
                return k == voicing.bass ? k7.accentIcon.opacity(0.5) : nil
            }
            for k in whites {
                let r = CGRect(x: x(k) + 0.5, y: 0, width: ww - 1, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(fill(k) ?? Color.white.opacity(0.92)))
            }
            for k in lo...hi where Self.black(k) {
                let r = CGRect(x: x(k), y: 0, width: bw, height: bh)
                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(fill(k) ?? Color.black))
            }
            func mark(_ text: String, under k: Int) {
                let mid = x(k) + (Self.black(k) ? bw : ww) / 2
                ctx.draw(Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(k7.textSecondary), at: CGPoint(x: mid, y: h + label / 2))
            }
            for (k, f) in zip(voicing.keys, voicing.fingers) { mark("\(f)", under: k) }
            if let b = voicing.bass { mark("L", under: b) }
        }
    }
}
