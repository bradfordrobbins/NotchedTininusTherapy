import SwiftUI

struct SpectrumView: View {
    var snapshot: SpectrumSnapshot
    var centerFrequency: Double
    var width: NotchWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spectrum")
                    .font(.headline)
                Spacer()
                Text("Gray before notch · Teal after")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Canvas { context, size in
                drawSpectrum(context: context, size: size)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Text("40 Hz")
                Spacer()
                Text("1 kHz")
                Spacer()
                Text("16 kHz")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func drawSpectrum(context: GraphicsContext, size: CGSize) {
        let band = SpectrumAnalyzer.notchBand(center: centerFrequency, width: width)
        let notchRect = CGRect(
            x: xPosition(for: band.low, width: size.width),
            y: 0,
            width: max(2, xPosition(for: band.high, width: size.width) - xPosition(for: band.low, width: size.width)),
            height: size.height
        )
        context.fill(
            Path(notchRect),
            with: .color(Color.orange.opacity(0.22))
        )

        let centerX = xPosition(for: centerFrequency, width: size.width)
        var centerLine = Path()
        centerLine.move(to: CGPoint(x: centerX, y: 0))
        centerLine.addLine(to: CGPoint(x: centerX, y: size.height))
        context.stroke(centerLine, with: .color(.orange.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

        if !snapshot.preBars.isEmpty {
            context.fill(barPath(snapshot.preBars, size: size), with: .color(Color.secondary.opacity(0.35)))
        }
        if !snapshot.postBars.isEmpty {
            context.fill(barPath(snapshot.postBars, size: size), with: .color(Color.accentColor.opacity(0.75)))
        } else {
            var hint = context
            hint.opacity = 0.6
            hint.draw(
                Text("Play a track to see the notch")
                    .font(.caption)
                    .foregroundColor(.secondary),
                at: CGPoint(x: size.width / 2, y: size.height / 2),
                anchor: .center
            )
        }
    }

    private func barPath(_ bars: [Float], size: CGSize) -> Path {
        let count = max(bars.count, 1)
        let barWidth = size.width / CGFloat(count)
        var path = Path()
        for (index, value) in bars.enumerated() {
            let height = CGFloat(value) * size.height
            let rect = CGRect(
                x: CGFloat(index) * barWidth,
                y: size.height - height,
                width: max(barWidth - 0.6, 0.4),
                height: height
            )
            path.addRect(rect)
        }
        return path
    }

    private func xPosition(for frequency: Double, width: CGFloat) -> CGFloat {
        let minHz = log(SpectrumAnalyzer.displayMinHz)
        let maxHz = log(SpectrumAnalyzer.displayMaxHz)
        let clamped = min(max(frequency, SpectrumAnalyzer.displayMinHz), SpectrumAnalyzer.displayMaxHz)
        let t = (log(clamped) - minHz) / (maxHz - minHz)
        return CGFloat(t) * width
    }
}
