import SwiftUI

struct HelpView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro
                    howToUse
                    findFrequency
                    listeningSchedule
                    whenYouNotice
                    research
                    disclaimer
                }
                .padding(24)
            }
            .navigationTitle("Help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 620, idealHeight: 720)
        #endif
    }

    private var intro: some View {
        section("Single-tone ringing therapy") {
            Text("This app is for **tonal tinnitus**: a single ringing, whistling, or buzzing pitch, not whooshing, pulsing, or several tones at once.")
            Text("Therapy removes a slice of sound around that pitch (a notch) from music or white noise. Neighboring frequencies keep playing and can inhibit the tinnitus pitch through lateral inhibition in the auditory cortex. That approach is called tailor-made notched music training.")
        }
    }

    private var howToUse: some View {
        section("How to use the app") {
            labeledStep("1", "Find Frequency") {
                Text("Match a sine tone to your ringing and tap Save Frequency. Therapy notches around that saved pitch.")
            }
            labeledStep("2", "Therapy") {
                Text("Play your own music folder or white noise. Pick a ½-octave or 1-octave notch. Use the spectrum to confirm the hole sits on your pitch. DRM streams (Apple Music, Spotify, YouTube) cannot be notched; use files you own.")
            }
            labeledStep("3", "Listening") {
                Text("The calendar logs minutes of notched therapy, not the finder tone. Aim for a steady daily total rather than one long session.")
            }
        }
    }

    private var findFrequency: some View {
        section("How to find your frequency") {
            Text("Work in a quiet room. Start the tone very quietly so you do not cover the ringing.")
            Text("On **Coarse search**, sweep slowly from low to high (200 Hz–16 kHz) until the tone and the tinnitus start to blend or the ringing seems quieter while the tone is on.")
            Text("Switch to **Fine Tune**. Nudge by 1 Hz until the tone and the ring become the same pitch — as if they occupy the same spot, not two notes next to each other.")
            Text("If you overshoot, go back to coarse search and try again. Save when it matches. Recheck after a few days; the first match is often close but not exact.")
            Text("White noise is useful if your music has little energy at a high pitch. The notch can only train frequencies that are actually present in the sound.")
            if settings.hasSavedFrequency {
                Text("Your saved match is \(FrequencyFormat.hertz(settings.tinnitusFrequency)).")
                    .fontWeight(.medium)
            }
        }
    }

    private var listeningSchedule: some View {
        section("How often and how long") {
            Text("Listen to notched music or notched white noise **1–2 hours per day**.")
            Text("Keep that up for **3 to 12 months**. This is a daily training routine, not a one-time filter. Missed weeks slow the adaptation the notch is meant to produce.")
        }
    }

    private var whenYouNotice: some View {
        section("When you may notice a change") {
            labeledStep(nil, "Initial noticeable shift") {
                Text("Many people notice a subtle drop in the perceived volume or harshness of the ringing within **1 to 3 weeks** of daily listening, as the auditory cortex begins adapting through lateral inhibition.")
            }
            labeledStep(nil, "Measurable clinical improvement") {
                Text("In structured clinical trials, statistically significant improvements on standardized scores (such as the Tinnitus Handicap Inventory) and loudness measures typically become clearer around **3 months** of consistent daily use.")
            }
            labeledStep(nil, "Long-term rewiring") {
                Text("Lasting suppression and cortical reorganization generally take **3 to 12 months** of the same routine.")
                Text(highFrequencyNote)
            }
            Text("These are typical timelines from published protocols, not a guarantee. People vary, and some do not improve.")
                .foregroundStyle(.secondary)
        }
    }

    private var research: some View {
        section("Research") {
            Text("The method comes from tailor-made notched music training (TMNMT) work led by Okamoto, Pantev, and colleagues.")
            Link(destination: Self.pnasPaper) {
                Text("Okamoto et al., 2010. Listening to tailor-made notched music reduces tinnitus loudness and tinnitus-related auditory cortex activity. Proceedings of the National Academy of Sciences.")
                    .multilineTextAlignment(.leading)
            }
            Link(destination: Self.clinicalTrial) {
                Text("Stein et al., 2016. Clinical trial on tonal tinnitus with tailor-made notched music training. BMC Neurology.")
                    .multilineTextAlignment(.leading)
            }
            Link(destination: Self.huangPaper) {
                Text("Huang et al., 2022. Notched sound alleviates tinnitus by reorganization emotional center. Frontiers in Human Neuroscience.")
                    .multilineTextAlignment(.leading)
            }
            Link(destination: Self.jiangReview) {
                Text("Jiang et al., 2025. The efficacy of notched music therapy vs conventional music therapy for chronic subjective tinnitus patients: a systematic review and meta-analysis. European Archives of Oto-Rhino-Laryngology.")
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var disclaimer: some View {
        Text("This is a self-help listening tool, not a diagnosis or medical treatment. It is intended for single-tone ringing. Stop if listening is uncomfortable, and talk with a clinician about tinnitus care.")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highFrequencyNote: String {
        let hz = settings.tinnitusFrequency
        if settings.hasSavedFrequency, hz >= 6_000 {
            return "Because your tinnitus is at \(FrequencyFormat.hertz(hz)), maintaining consistency is key. High-frequency matches sit near the edge of standard audio processing and need steady daily exposure to drive neural plasticity."
        }
        return "If your tinnitus is in the high range (around 8 kHz or above), consistency matters even more. Those pitches sit near the edge of standard audio processing and need steady daily exposure to drive neural plasticity."
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func labeledStep(_ number: String?, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let number {
                    Text(number)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20, alignment: .leading)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            content()
                .font(.body)
        }
    }

    private static let pnasPaper = URL(string: "https://doi.org/10.1073/pnas.0911268107")!
    private static let clinicalTrial = URL(string: "https://doi.org/10.1186/s12883-016-0558-7")!
    private static let huangPaper = URL(string: "https://doi.org/10.3389/fnhum.2021.762492")!
    private static let jiangReview = URL(string: "https://doi.org/10.1007/s00405-025-09260-9")!
}

struct HelpSheetModifier: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        isPresented = true
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .help("How to use Tininus Notch")
                }
            }
            .sheet(isPresented: $isPresented) {
                HelpView()
            }
    }
}

extension View {
    func helpSheet() -> some View {
        modifier(HelpSheetModifier())
    }
}

#Preview {
    HelpView()
        .environment(AppSettings())
}
