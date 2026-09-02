import SwiftUI

struct FindFrequencyView: View {
    @Environment(AppSettings.self) private var settings
    let sineEngine: SineToneEngine

    @State private var workingFrequency = FrequencyRange.defaultFrequency
    @State private var isFineTune = false
    @State private var fineCenter = FrequencyRange.defaultFrequency
    @State private var isPlaying = false
    @State private var didSave = false
    @State private var playError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    frequencyReadout
                    if isFineTune {
                        fineTuneControls
                    } else {
                        coarseControls
                    }
                    volumeControls
                    transport
                    saveSection
                    disclaimer
                }
                .padding(24)
            }
            .navigationTitle("Find Frequency")
            .helpSheet()
            .onAppear {
                workingFrequency = settings.tinnitusFrequency
                sineEngine.setFrequency(workingFrequency)
                sineEngine.setVolume(settings.toneVolume)
            }
            .onDisappear {
                sineEngine.stop()
                isPlaying = false
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Match the tone to your tinnitus")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Start quietly. Use coarse search first, then fine-tune until the tone and the tinnitus blend.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var frequencyReadout: some View {
        VStack(spacing: 6) {
            Text(FrequencyFormat.hertz(workingFrequency))
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .monospacedDigit()
            Text(isFineTune ? "Fine tune" : "Coarse search")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var coarseControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approximate frequency")
                .font(.headline)
            Slider(
                value: logSliderBinding,
                in: 0...1
            )
            HStack {
                Text(FrequencyFormat.hertz(FrequencyRange.minimum))
                Spacer()
                Text(FrequencyFormat.hertz(FrequencyRange.maximum))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Fine Tune") {
                fineCenter = workingFrequency
                isFineTune = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var fineTuneControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fine tune around \(FrequencyFormat.hertz(fineCenter))")
                .font(.headline)
            Slider(
                value: $workingFrequency,
                in: fineLower...fineUpper,
                step: 1
            )
            .onChange(of: workingFrequency) { _, value in
                applyFrequency(value)
            }
            HStack {
                Text(FrequencyFormat.hertz(fineLower))
                Spacer()
                Text(FrequencyFormat.hertz(fineUpper))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button {
                    applyFrequency(workingFrequency - 1)
                } label: {
                    Label("−1 Hz", systemImage: "minus")
                }
                .disabled(workingFrequency <= fineLower)

                Button {
                    applyFrequency(workingFrequency + 1)
                } label: {
                    Label("+1 Hz", systemImage: "plus")
                }
                .disabled(workingFrequency >= fineUpper)
            }
            .buttonStyle(.bordered)

            Button("Back to coarse search") {
                isFineTune = false
            }
            .buttonStyle(.borderless)
        }
    }

    private var volumeControls: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 8) {
            Text("Tone volume")
                .font(.headline)
            Slider(value: $settings.toneVolume, in: 0...1)
                .onChange(of: settings.toneVolume) { _, value in
                    sineEngine.setVolume(value)
                }
            Text("Starts low on purpose. Raise it only as far as you need to hear the match.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        VStack(spacing: 8) {
            Button {
                if isPlaying {
                    sineEngine.stop()
                    isPlaying = false
                } else {
                    sineEngine.setFrequency(workingFrequency)
                    sineEngine.setVolume(settings.toneVolume)
                    do {
                        try sineEngine.start()
                        isPlaying = true
                        playError = nil
                    } catch {
                        isPlaying = false
                        playError = error.localizedDescription
                    }
                }
            } label: {
                Label(isPlaying ? "Stop Tone" : "Play Tone", systemImage: isPlaying ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let playError {
                Text(playError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var saveSection: some View {
        VStack(spacing: 10) {
            Button("Save Frequency") {
                settings.saveFrequency(workingFrequency)
                didSave = true
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if settings.hasSavedFrequency {
                Text("Saved for therapy: \(FrequencyFormat.hertz(settings.tinnitusFrequency))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if didSave {
                Text("Saved. This frequency is used when you play notched music.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var disclaimer: some View {
        Text("This is a self-help listening tool, not medical advice. Stop if the sound is uncomfortable and talk with a clinician about tinnitus care.")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private var logSliderBinding: Binding<Double> {
        Binding(
            get: {
                let minLog = log(FrequencyRange.minimum)
                let maxLog = log(FrequencyRange.maximum)
                return (log(workingFrequency) - minLog) / (maxLog - minLog)
            },
            set: { newValue in
                let minLog = log(FrequencyRange.minimum)
                let maxLog = log(FrequencyRange.maximum)
                applyFrequency(exp(minLog + newValue * (maxLog - minLog)))
            }
        )
    }

    private var fineLower: Double {
        FrequencyRange.clamp(fineCenter / pow(2.0, 1.0 / 12.0))
    }

    private var fineUpper: Double {
        FrequencyRange.clamp(fineCenter * pow(2.0, 1.0 / 12.0))
    }

    private func applyFrequency(_ hz: Double) {
        workingFrequency = FrequencyRange.clamp(hz)
        sineEngine.setFrequency(workingFrequency)
        didSave = false
    }
}
