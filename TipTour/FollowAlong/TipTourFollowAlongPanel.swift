import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class TipTourFollowAlongWindowManager {
    private weak var companionManager: CompanionManager?
    private var window: NSWindow?
    private var runner: TipTourFollowAlongRunner?
    private let initialWindowSize = NSSize(width: 980, height: 680)
    private let minimumWindowSize = NSSize(width: 820, height: 560)

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
    }

    func show() {
        guard let companionManager else { return }

        if window == nil {
            createWindow(companionManager: companionManager)
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow(companionManager: CompanionManager) {
        let runner = TipTourFollowAlongRunner(engine: companionManager.tipTourEngine)
        self.runner = runner

        let hostingView = NSHostingView(rootView: TipTourFollowAlongWindowView(runner: runner))
        hostingView.frame = NSRect(origin: .zero, size: initialWindowSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.sizingOptions = [.intrinsicContentSize]

        let followWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        followWindow.title = "TipTour Follow Along"
        followWindow.titleVisibility = .hidden
        followWindow.titlebarAppearsTransparent = true
        followWindow.isReleasedWhenClosed = false
        followWindow.backgroundColor = .clear
        followWindow.isOpaque = false
        followWindow.hasShadow = true
        followWindow.minSize = minimumWindowSize
        followWindow.contentMinSize = minimumWindowSize
        followWindow.setFrameAutosaveName("TipTourFollowAlongWindow")
        followWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        followWindow.contentView = hostingView

        window = followWindow
    }
}

struct TipTourFollowAlongWindowView: View {
    @ObservedObject var runner: TipTourFollowAlongRunner

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                header
                sourceControls

                HStack(alignment: .top, spacing: 14) {
                    transcriptEditor
                    stepsPanel
                }

                footerControls
            }
            .padding(22)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(DS.Colors.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("Follow Along")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Text("Paste a tutorial transcript or load a YouTube transcript, then run each generated action through TipTour.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            Toggle("Repair", isOn: $runner.autoRepair)
                .toggleStyle(.switch)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
                .help("When a step fails, ask the planner for the next repair action using the current visible targets.")

            Toggle("AI draft", isOn: $runner.useAIPlanner)
                .toggleStyle(.switch)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
                .help("Uses your saved Claude key when available; deterministic parsing is used as the fallback.")
        }
    }

    private var sourceControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("YouTube link", text: $runner.youtubeURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(inputBackground)

                Button {
                    runner.loadYouTubeTranscript()
                } label: {
                    Label("Load", systemImage: "arrow.down.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(FollowAlongButtonStyle())
                .disabled(runner.isBusy || runner.youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    runner.enrichVideoContext()
                } label: {
                    Label("Enrich", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(FollowAlongButtonStyle())
                .disabled(runner.isBusy || runner.youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Extract sampled video frames and ask the saved OpenRouter/Qwen vision model for grounding context.")
            }

            HStack(spacing: 8) {
                TextField("Target app, e.g. Blender, Xcode, Notes", text: $runner.targetApp)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(inputBackground)

                Button {
                    runner.generateSteps()
                } label: {
                    Label("Convert", systemImage: "wand.and.stars")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(FollowAlongButtonStyle())
                .disabled(runner.isBusy || runner.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    runner.runAllSteps()
                } label: {
                    Label("Run", systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(FollowAlongButtonStyle(isPrimary: true))
                .disabled(runner.isBusy || runner.steps.isEmpty)

                Button {
                    runner.runNextStep()
                } label: {
                    Label("Next", systemImage: "forward.end.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(FollowAlongButtonStyle())
                .disabled(runner.isBusy || !runner.hasRunnableStep)

                Button {
                    runner.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(FollowAlongButtonStyle())
                .disabled(!runner.isBusy)
            }

            if !runner.enrichmentSummary.isEmpty {
                HStack(spacing: 8) {
                    Text("Video context")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DS.Colors.accent)

                    Text(runner.enrichmentSummary)
                        .font(.system(size: 10))
                        .foregroundColor(DS.Colors.textTertiary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        runner.copyEnrichmentSummary()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DS.Colors.textTertiary)
                    .help("Copy video enrichment context")
                }
            }
        }
    }

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript / Script")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Colors.textSecondary)

            TextEditor(text: $runner.transcriptText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(DS.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(editorBackground)
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var stepsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Steps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textSecondary)

                Spacer()

                Button {
                    runner.copyStepsAsText()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundColor(DS.Colors.textTertiary)
                .help("Copy readable steps")

                Button {
                    runner.copyStepsAsJSON()
                } label: {
                    Image(systemName: "curlybraces")
                }
                .buttonStyle(.plain)
                .foregroundColor(DS.Colors.textTertiary)
                .help("Copy JSON steps")

                Button {
                    runner.copyTraceAsJSONL()
                } label: {
                    Image(systemName: "list.clipboard")
                }
                .buttonStyle(.plain)
                .foregroundColor(DS.Colors.textTertiary)
                .help("Copy latest run trace")
                .disabled(!runner.hasTrace)

                Button {
                    runner.copyTraceEvaluation()
                } label: {
                    Image(systemName: "checkmark.seal")
                }
                .buttonStyle(.plain)
                .foregroundColor(DS.Colors.textTertiary)
                .help("Copy latest run evaluation")
                .disabled(!runner.hasTrace)

                Text("\(runner.steps.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(runner.steps.enumerated()), id: \.element.id) { index, step in
                        FollowAlongStepRow(index: index, step: step)
                    }
                }
                .padding(10)
            }
            .background(editorBackground)
            .frame(minWidth: 340, maxWidth: 420, maxHeight: .infinity)
        }
    }

    private var footerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(runner.statusText)
                .font(.system(size: 11))
                .foregroundColor(runner.isBusy ? DS.Colors.accent : DS.Colors.textTertiary)
                .lineLimit(2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(runner.logLines.suffix(8), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(DS.Colors.textTertiary)
                    }
                }
            }
            .frame(height: 18)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DS.Colors.borderSubtle.opacity(0.75), lineWidth: 0.7)
            )
    }

    private var editorBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Colors.borderSubtle.opacity(0.7), lineWidth: 0.7)
            )
    }
}

private struct FollowAlongStepRow: View {
    let index: Int
    let step: TipTourFollowAlongStep

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 24, alignment: .leading)

                Text(step.workflowStep.type.rawValue)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(DS.Colors.textSecondary)

                Spacer()

                Text(step.status.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(step.status.color)
            }

            Text(step.displayText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.Colors.textPrimary)
                .lineLimit(2)

            if let message = step.message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}

private struct FollowAlongButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(isPrimary ? Color.white : DS.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isPrimary ? DS.Colors.accent.opacity(configuration.isPressed ? 0.72 : 0.92) : Color.white.opacity(configuration.isPressed ? 0.1 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DS.Colors.borderSubtle.opacity(isPrimary ? 0.2 : 0.7), lineWidth: 0.7)
            )
    }
}

private extension TipTourFollowAlongStep.Status {
    var color: Color {
        switch self {
        case .pending:
            return DS.Colors.textTertiary
        case .running:
            return DS.Colors.accent
        case .ok:
            return DS.Colors.success
        case .repaired:
            return DS.Colors.warningText
        case .failed:
            return DS.Colors.destructiveText
        case .skipped:
            return DS.Colors.textTertiary
        }
    }
}

struct TipTourFollowAlongStep: Identifiable, Hashable {
    enum Status: String, Hashable {
        case pending
        case running
        case ok
        case repaired
        case failed
        case skipped
    }

    let id: String
    var sourceText: String
    let app: String?
    var workflowStep: WorkflowStep
    var status: Status
    var message: String?

    init(sourceText: String, app: String?, workflowStep: WorkflowStep) {
        self.id = UUID().uuidString
        self.sourceText = sourceText
        self.app = app
        self.workflowStep = workflowStep
        self.status = .pending
        self.message = nil
    }

    var displayText: String {
        if !workflowStep.hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return workflowStep.hint
        }
        if let value = workflowStep.value, !value.isEmpty {
            return value
        }
        if let label = workflowStep.label, !label.isEmpty {
            return label
        }
        return sourceText
    }
}

@MainActor
final class TipTourFollowAlongRunner: ObservableObject {
    @Published var youtubeURL = ""
    @Published var targetApp = ""
    @Published var transcriptText = ""
    @Published var steps: [TipTourFollowAlongStep] = []
    @Published var useAIPlanner = true
    @Published var autoRepair = true
    @Published private(set) var enrichmentSummary = ""
    @Published private(set) var latestTracePath = ""
    @Published private(set) var isBusy = false
    @Published private(set) var statusText = "Paste a script or load a YouTube transcript."
    @Published private(set) var logLines: [String] = []

    var hasRunnableStep: Bool {
        steps.contains { $0.status == .pending || $0.status == .failed }
    }

    var hasTrace: Bool {
        !latestTracePath.isEmpty
    }

    private let engine: TipTourEngine
    private let aiPlanner = TipTourFollowAlongAIPlannerClient()
    private let contextEnricher = TipTourFollowAlongContextEnricher()
    private let traceStore = TipTourFollowAlongTraceStore.shared
    private let traceEvaluator = TipTourFollowAlongTraceEvaluator()
    private var currentTraceRunID = TipTourFollowAlongTraceStore.shared.makeRunID()
    private var visualHistory: [TipTourFollowAlongVisualHistoryItem] = []
    private var lastDistinctPreState: TipTourFollowAlongTraceStore.StateSnapshot?
    private var activeTask: Task<Void, Never>?

    init(engine: TipTourEngine) {
        self.engine = engine
    }

    func loadYouTubeTranscript() {
        guard !isBusy else { return }
        let rawURL = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else { return }

        activeTask?.cancel()
        activeTask = Task {
            isBusy = true
            statusText = "Loading YouTube transcript..."
            appendLog("youtube: start")
            defer { isBusy = false }

            do {
                let result = try await TipTourYouTubeTranscriptLoader.loadTranscript(from: rawURL)
                transcriptText = result.transcript
                statusText = "Loaded transcript using \(result.source)."
                appendLog("youtube: loaded via \(result.source)")
                PipelineLogStore.shared.record(
                    category: "follow_along",
                    name: "youtube_transcript",
                    status: "ok",
                    message: "Loaded YouTube transcript.",
                    metadata: [
                        "source": result.source,
                        "character_count": String(result.transcript.count)
                    ]
                )
            } catch {
                statusText = error.localizedDescription
                appendLog("youtube: failed")
                PipelineLogStore.shared.record(
                    category: "follow_along",
                    name: "youtube_transcript",
                    status: "failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func enrichVideoContext() {
        guard !isBusy else { return }
        let rawURL = youtubeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else { return }
        guard let apiKey = KeychainStore.openRouterAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            statusText = "Save an OpenRouter key in Settings before enriching video context."
            appendLog("enrich: missing OpenRouter key")
            return
        }

        activeTask?.cancel()
        activeTask = Task {
            isBusy = true
            statusText = "Extracting video frames..."
            appendLog("enrich: frames")
            defer { isBusy = false }

            do {
                let transcript = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
                let app = targetApp.trimmingCharacters(in: .whitespacesAndNewlines)
                let result = try await contextEnricher.enrich(
                    youtubeURL: rawURL,
                    transcript: transcript.isEmpty ? "No transcript loaded yet." : transcript,
                    targetAppName: app.isEmpty ? nil : app,
                    openRouterAPIKey: apiKey,
                    maxFrames: 8
                )
                enrichmentSummary = result.enrichment.plannerContext
                statusText = "Enriched video context from \(result.frameExtraction.frames.count) frame(s) with \(result.enrichment.model)."
                appendLog("enrich: \(result.frameExtraction.frames.count) frames")
                PipelineLogStore.shared.record(
                    category: "follow_along",
                    name: "video_context_enrichment",
                    status: "ok",
                    message: "Enriched follow-along context from YouTube frames.",
                    metadata: [
                        "frame_count": String(result.frameExtraction.frames.count),
                        "model": result.enrichment.model,
                        "directory_path": result.frameExtraction.directory.path,
                        "summary_characters": String(result.enrichment.plannerContext.count)
                    ]
                )
            } catch {
                statusText = error.localizedDescription
                appendLog("enrich: failed")
                PipelineLogStore.shared.record(
                    category: "follow_along",
                    name: "video_context_enrichment",
                    status: "failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func generateSteps() {
        guard !isBusy else { return }
        let script = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { return }

        activeTask?.cancel()
        activeTask = Task {
            isBusy = true
            statusText = "Converting transcript into steps..."
            appendLog("convert: start")
            defer { isBusy = false }

            do {
                let defaultApp = targetApp.trimmingCharacters(in: .whitespacesAndNewlines)
                let generatedSteps: [TipTourFollowAlongStep]
                if useAIPlanner, let apiKey = KeychainStore.claudeAPIKey, !apiKey.isEmpty {
                    let plan = try await aiPlanner.planSteps(
                        transcript: plannerInput(from: script),
                        targetAppName: defaultApp.isEmpty ? nil : defaultApp,
                        apiKey: apiKey
                    )
                    generatedSteps = TipTourFollowAlongScriptParser.steps(from: plan, fallbackApp: defaultApp)
                    appendLog("convert: ai")
                } else {
                    generatedSteps = TipTourFollowAlongScriptParser.steps(
                        fromTranscript: script,
                        defaultApp: defaultApp
                    )
                    appendLog("convert: rules")
                }

                steps = generatedSteps
                resetTraceRun()
                statusText = generatedSteps.isEmpty
                    ? "No executable steps found. Try shorter imperative lines like \"click Add\" or \"press Cmd+S\"."
                    : "Generated \(generatedSteps.count) step(s)."
                PipelineLogStore.shared.record(
                    category: "follow_along",
                    name: "convert_transcript",
                    status: generatedSteps.isEmpty ? "failed" : "ok",
                    message: statusText,
                    metadata: ["step_count": String(generatedSteps.count)]
                )
            } catch {
                let defaultApp = targetApp.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackSteps = TipTourFollowAlongScriptParser.steps(
                    fromTranscript: script,
                    defaultApp: defaultApp
                )
                steps = fallbackSteps
                resetTraceRun()
                statusText = "AI conversion failed, used rule parser: \(error.localizedDescription)"
                appendLog("convert: ai failed, rules")
            }
        }
    }

    func runAllSteps() {
        guard !isBusy else { return }
        guard !steps.isEmpty else { return }

        activeTask?.cancel()
        activeTask = Task {
            isBusy = true
            statusText = "Running follow-along steps..."
            appendLog("run: start")
            resetTraceRun()
            defer {
                isBusy = false
                activeTask = nil
            }

            var index = 0
            while index < steps.count {
                if steps[index].status == .ok || steps[index].status == .repaired || steps[index].status == .skipped {
                    index += 1
                    continue
                }
                if Task.isCancelled {
                    steps[index].status = .skipped
                    steps[index].message = "Stopped."
                    break
                }
                await runStep(at: index)
                if steps[index].status == .failed {
                    statusText = "Stopped at step \(index + 1). Fix app state or copy steps/logs for debug."
                    appendLog("run: stopped at failed step \(index + 1)")
                    break
                }
                if steps[index].status == .skipped {
                    statusText = "Stopped at manual checkpoint \(index + 1). Do that part, then click Next."
                    appendLog("run: stopped at manual checkpoint \(index + 1)")
                    break
                }
                index += 1
                try? await Task.sleep(nanoseconds: 850_000_000)
            }

            if !Task.isCancelled {
                if steps.contains(where: { $0.status == .failed }) {
                    statusText = "Follow-along run stopped on a failed step."
                } else if steps.contains(where: { $0.status == .skipped }) {
                    statusText = "Follow-along run stopped on a manual checkpoint."
                } else {
                    statusText = "Follow-along run finished."
                }
                appendLog("run: finished")
            }
        }
    }

    func runNextStep() {
        guard !isBusy,
              let index = steps.firstIndex(where: { $0.status == .pending || $0.status == .failed }) else {
            return
        }

        activeTask?.cancel()
        activeTask = Task {
            isBusy = true
            statusText = "Running step \(index + 1)..."
            appendLog("next: step \(index + 1)")
            defer {
                isBusy = false
                activeTask = nil
            }
            await runStep(at: index)
            if steps[index].status == .failed {
                statusText = "Step \(index + 1) failed. Copy JSON/logs and inspect the exact target."
            } else {
                statusText = "Step \(index + 1) finished."
            }
        }
    }

    func stop() {
        activeTask?.cancel()
        WorkflowRunner.shared.stop()
        isBusy = false
        statusText = "Stopped follow-along run."
        appendLog("run: stopped")
    }

    func copyStepsAsText() {
        let text = steps.enumerated().map { index, step in
            let workflowStep = step.workflowStep
            let payload = workflowStep.value ?? workflowStep.label ?? ""
            return "\(index + 1). \(workflowStep.type.rawValue) \(payload) — \(step.displayText)"
        }
        .joined(separator: "\n")
        copyToPasteboard(text)
        statusText = "Copied readable steps."
    }

    func copyStepsAsJSON() {
        let defaultApp = targetApp.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = WorkflowPlan(
            goal: "Follow along tutorial",
            app: defaultApp.isEmpty ? nil : defaultApp,
            steps: steps.map(\.workflowStep)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(plan),
              let text = String(data: data, encoding: .utf8) else {
            statusText = "Could not encode steps."
            return
        }
        copyToPasteboard(text)
        statusText = "Copied JSON steps."
    }

    func copyEnrichmentSummary() {
        guard !enrichmentSummary.isEmpty else { return }
        copyToPasteboard(enrichmentSummary)
        statusText = "Copied video enrichment context."
    }

    func copyTraceAsJSONL() {
        do {
            let text = try traceStore.readTrace(runID: currentTraceRunID)
            copyToPasteboard(text)
            statusText = "Copied follow-along trace JSONL."
        } catch {
            statusText = "No follow-along trace is available yet."
        }
    }

    func copyTraceEvaluation() {
        do {
            let text = try traceStore.readTrace(runID: currentTraceRunID)
            let report = traceEvaluator.evaluate(jsonl: text)
            copyToPasteboard(report.text)
            statusText = "Copied follow-along trace evaluation."
        } catch {
            statusText = "No follow-along trace is available yet."
        }
    }

    private func runStep(at index: Int) async {
        guard steps.indices.contains(index) else { return }
        var currentIndex = index
        var repairAttempts = 0
        let maximumRepairAttempts = autoRepair ? 2 : 0

        while steps.indices.contains(currentIndex) {
            if await resolveObserveCheckpointIfNeeded(at: currentIndex, attemptNumber: repairAttempts + 1) == false {
                return
            }

            let execution = await executeStep(at: currentIndex)
            if execution.ok { return }

            guard repairAttempts < maximumRepairAttempts else {
                steps[currentIndex].status = .failed
                steps[currentIndex].message = execution.message
                appendLog("step \(currentIndex + 1): failed")
                return
            }

            repairAttempts += 1
            appendLog("step \(currentIndex + 1): ai repair \(repairAttempts)")
            let repair = await repairWorkflowStep(
                failedStepIndex: currentIndex,
                failureMessage: execution.message ?? "The step failed.",
                attemptNumber: repairAttempts
            )

            switch repair {
            case .none:
                let localRepair = await repairStep(steps[currentIndex], app: normalizedApp(steps[currentIndex].app))
                if localRepair.ok {
                    steps[currentIndex].status = .repaired
                    steps[currentIndex].message = localRepair.message ?? "Repaired with grounded action."
                    return
                }
                steps[currentIndex].status = .failed
                steps[currentIndex].message = localRepair.message ?? execution.message
                return

            case .insertBefore(let repairStep, let reason):
                steps.insert(repairStep, at: currentIndex)
                steps[currentIndex].message = "Repair inserted: \(reason)"
                let repairExecution = await executeStep(at: currentIndex)
                if repairExecution.ok {
                    steps[currentIndex].status = .repaired
                    steps[currentIndex].message = "Repair action succeeded. Retrying original step."
                    currentIndex += 1
                    continue
                }
                steps[currentIndex].status = .failed
                steps[currentIndex].message = repairExecution.message ?? "Inserted repair step failed."
                return

            case .replace(let repairStep, let reason):
                steps[currentIndex].workflowStep = repairStep.workflowStep
                steps[currentIndex].sourceText = repairStep.sourceText
                steps[currentIndex].status = .running
                steps[currentIndex].message = "Repair replacement: \(reason)"
                continue

            case .skip(let reason):
                steps[currentIndex].status = .skipped
                steps[currentIndex].message = reason
                return
            }
        }
    }

    private func resolveObserveCheckpointIfNeeded(at index: Int, attemptNumber: Int) async -> Bool {
        guard autoRepair,
              steps.indices.contains(index),
              steps[index].workflowStep.type == .observe else {
            return true
        }

        appendLog("step \(index + 1): resolve observe")
        let repair = await repairWorkflowStep(
            failedStepIndex: index,
            failureMessage: "This draft step is an observe checkpoint. Convert it into one executable desktop action if possible. If it is only a visual/manual checkpoint, skip it.",
            attemptNumber: attemptNumber
        )

        switch repair {
        case .none:
            steps[index].status = .skipped
            steps[index].message = "Skipped observe checkpoint because no concrete repair action was available."
            return false

        case .skip(let reason):
            steps[index].status = .skipped
            steps[index].message = reason
            return false

        case .insertBefore(let repairStep, let reason), .replace(let repairStep, let reason):
            if repairStep.workflowStep.type == .observe {
                steps[index].status = .skipped
                steps[index].message = "Repair planner kept this as observe: \(reason)"
                return false
            }
            steps[index].workflowStep = repairStep.workflowStep
            steps[index].sourceText = repairStep.sourceText
            steps[index].status = .running
            steps[index].message = "Observe resolved: \(reason)"
            return true
        }
    }

    private func executeStep(at index: Int) async -> (ok: Bool, message: String?) {
        guard steps.indices.contains(index) else {
            return (false, "Step index is no longer valid.")
        }
        steps[index].status = .running
        steps[index].message = nil

        let step = steps[index]
        let app = normalizedApp(step.app)
        let traceID = TipTourActionTrace.makeID(source: "follow")
        let preState = await followAlongStateSnapshot(
            traceID: "\(traceID)_pre",
            step: step,
            app: app,
            reason: "follow_along_pre_action"
        )
        let stateActionState = stateActionMatchedState(for: preState)
        let preparedStep: WorkflowStep
        do {
            preparedStep = try await preparedWorkflowStep(for: step, app: app)
        } catch {
            steps[index].status = .failed
            steps[index].message = error.localizedDescription
            appendLog("step \(index + 1): preflight failed")
            recordTrace(
                runID: currentTraceRunID,
                traceID: traceID,
                stepIndex: index,
                step: step,
                app: app,
                preparedStep: nil,
                preState: preState,
                stateActionState: stateActionState,
                postState: nil,
                result: .preflightFailure(error.localizedDescription)
            )
            return (false, error.localizedDescription)
        }
        let plan = WorkflowPlan(
            goal: step.sourceText,
            app: app,
            steps: [preparedStep],
            traceID: traceID
        )

        PipelineLogStore.shared.record(
            category: "follow_along",
            name: "step",
            status: "started",
            message: step.sourceText,
            metadata: [
                TipTourActionTrace.metadataKey: traceID,
                "step_index": String(index + 1),
                "step_count": String(steps.count),
                "app": app ?? "",
                "action_type": preparedStep.type.rawValue,
                "label": preparedStep.label ?? "",
                "target_id": preparedStep.targetID ?? "",
                "target_mark": preparedStep.targetMark.map(String.init) ?? "",
                "value_preview": preparedStep.value.map { String($0.prefix(120)) } ?? ""
            ]
        )

        let result = await engine.submitSingleActionWorkflowPlanAndWait(plan)
        let postState = await followAlongStateSnapshot(
            traceID: "\(traceID)_post",
            step: step,
            app: app,
            reason: "follow_along_post_action"
        )
        recordTrace(
            runID: currentTraceRunID,
            traceID: traceID,
            stepIndex: index,
            step: step,
            app: app,
            preparedStep: preparedStep,
            preState: preState,
            stateActionState: stateActionState,
            postState: postState,
            result: TipTourFollowAlongTraceStore.ResultSummary(submission: result)
        )
        if result.ok {
            steps[index].status = .ok
            steps[index].message = result.message
            appendLog("step \(index + 1): ok")
            return (true, result.message)
        }

        let failureMessage = result.message ?? result.reason ?? "Failed."
        steps[index].status = .failed
        steps[index].message = failureMessage
        return (false, failureMessage)
    }

    private func followAlongStateSnapshot(
        traceID: String,
        step: TipTourFollowAlongStep,
        app: String?,
        reason: String
    ) async -> TipTourFollowAlongTraceStore.StateSnapshot {
        let visualContext = await engine.visualContext(
            intent: step.sourceText,
            app: app,
            requestedMode: "auto",
            reason: reason,
            targetLabel: step.workflowStep.label,
            targetID: step.workflowStep.targetID,
            targetMark: step.workflowStep.targetMark,
            refresh: true,
            traceID: traceID
        )
        let targetList = await engine.localPerceptionTargets(
            refresh: false,
            reason: "follow-along trace \(reason)"
        )
        updateVisualHistory(visualContext: visualContext, targets: targetList.targets)
        return TipTourFollowAlongTraceStore.StateSnapshot(
            visualContext: visualContext,
            fullTargets: targetList.targets
        )
    }

    private func recordTrace(
        runID: String,
        traceID: String,
        stepIndex: Int,
        step: TipTourFollowAlongStep,
        app: String?,
        preparedStep: WorkflowStep?,
        preState: TipTourFollowAlongTraceStore.StateSnapshot,
        stateActionState: TipTourFollowAlongTraceStore.StateSnapshot,
        postState: TipTourFollowAlongTraceStore.StateSnapshot?,
        result: TipTourFollowAlongTraceStore.ResultSummary
    ) {
        let chosenTarget = preparedStep.flatMap {
            chosenTargetSummary(for: $0, stateActionState: stateActionState, postState: postState)
        }
        let record = TipTourFollowAlongTraceStore.Record(
            schemaVersion: 1,
            timestamp: Self.isoTimestamp(),
            runID: runID,
            traceID: traceID,
            stepIndex: stepIndex + 1,
            stepCount: steps.count,
            sourceText: step.sourceText,
            targetApp: app,
            draftStep: step.workflowStep,
            preparedStep: preparedStep,
            preState: preState,
            stateActionState: stateActionState,
            postState: postState,
            chosenTarget: chosenTarget,
            result: result
        )

        do {
            let fileURL = try traceStore.append(record)
            latestTracePath = fileURL.path
            PipelineLogStore.shared.record(
                category: "follow_along",
                name: "trace_record",
                status: "ok",
                message: "Saved follow-along trace record.",
                metadata: [
                    "run_id": runID,
                    TipTourActionTrace.metadataKey: traceID,
                    "step_index": String(stepIndex + 1),
                    "path": fileURL.path,
                    "result": result.status
                ]
            )
        } catch {
            appendLog("trace: failed")
            PipelineLogStore.shared.record(
                category: "follow_along",
                name: "trace_record",
                status: "failed",
                message: error.localizedDescription,
                metadata: [
                    "run_id": runID,
                    TipTourActionTrace.metadataKey: traceID,
                    "step_index": String(stepIndex + 1)
                ]
            )
        }
    }

    private func chosenTargetSummary(
        for step: WorkflowStep,
        stateActionState: TipTourFollowAlongTraceStore.StateSnapshot,
        postState: TipTourFollowAlongTraceStore.StateSnapshot?
    ) -> TipTourFollowAlongTraceStore.TargetSummary? {
        let targets = stateActionState.targets + (postState?.targets ?? [])
        if let targetID = step.targetID?.trimmingCharacters(in: .whitespacesAndNewlines), !targetID.isEmpty {
            return targets.first { $0.id == targetID }
        }
        if let targetMark = step.targetMark {
            return targets.first { $0.mark == targetMark }
        }
        return nil
    }

    private func preparedWorkflowStep(for step: TipTourFollowAlongStep, app: String?) async throws -> WorkflowStep {
        var preGroundTargets: [LocalPerceptionTargetCache.SnapshotTarget] = []
        var workflowStep = normalizedWorkflowStepForExecution(
            step.workflowStep,
            sourceText: step.sourceText,
            app: app,
            visibleTargets: []
        )
        if shouldPreGround(workflowStep) {
            try? await Task.sleep(nanoseconds: 650_000_000)
            let targetList = await engine.localPerceptionTargets(
                refresh: true,
                reason: "follow-along pre-ground"
            )
            preGroundTargets = targetList.targets
            workflowStep = normalizedWorkflowStepForExecution(
                step.workflowStep,
                sourceText: step.sourceText,
                app: app,
                visibleTargets: targetList.targets
            )
        }

        if shouldPreGround(workflowStep), let label = workflowStep.label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let target = localPreGroundTarget(for: workflowStep, label: label, targets: preGroundTargets) {
                return workflowStepWithTarget(workflowStep, target: TipTourEngineGroundedTarget(target))
            }

            let grounded = await engine.groundTarget(
                goal: step.sourceText,
                app: app,
                actionType: workflowStep.type,
                targetLabel: label,
                targetID: workflowStep.targetID,
                targetMark: workflowStep.targetMark,
                refresh: false,
                allowScreenshotPlanning: true,
                allowAIMatch: true
            )
            guard grounded.ok, let target = grounded.target else {
                throw NSError(
                    domain: "TipTourFollowAlongRunner",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: grounded.message ?? "Could not ground \"\(label)\" before running this step."
                    ]
                )
            }
            guard didGroundExpectedTarget(requestedLabel: label, target: target, step: workflowStep) else {
                throw NSError(
                    domain: "TipTourFollowAlongRunner",
                    code: -2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Rejected unsafe target match: requested \"\(label)\", got \"\(target.label)\"."
                    ]
                )
            }
            return workflowStepWithTarget(workflowStep, target: target)
        }

        if shouldRefreshAfterTargetlessMenuAction(workflowStep) {
            try? await Task.sleep(nanoseconds: 650_000_000)
        }
        return workflowStep
    }

    private func normalizedWorkflowStepForExecution(
        _ step: WorkflowStep,
        sourceText: String,
        app: String?,
        visibleTargets: [LocalPerceptionTargetCache.SnapshotTarget]
    ) -> WorkflowStep {
        if let rewrite = MarkdownAppSkillRegistry.shared
            .skill(applicationName: app)
            .flatMap({
                $0.followAlongRewrite(
                    for: step,
                    sourceText: sourceText,
                    visibleTargets: visibleTargets
                )
            }) {
            return replacingWorkflowStep(
                step,
                type: rewrite.type,
                label: rewrite.label,
                value: rewrite.value,
                targetContext: rewrite.targetContext
            )
        }

        return step
    }

    private func replacingWorkflowStep(
        _ step: WorkflowStep,
        type: WorkflowStep.StepType,
        label: String?,
        value: String?,
        targetContext: WorkflowStep.TargetContext?
    ) -> WorkflowStep {
        WorkflowStep(
            id: step.id,
            type: type,
            label: label,
            targetID: nil,
            targetMark: nil,
            value: value,
            direction: step.direction,
            amount: step.amount,
            by: step.by,
            targetContext: targetContext,
            hint: step.hint,
            hintX: nil,
            hintY: nil,
            box2DNormalized: nil,
            screenNumber: step.screenNumber
        )
    }

    private func didGroundExpectedTarget(
        requestedLabel: String,
        target: TipTourEngineGroundedTarget,
        step: WorkflowStep
    ) -> Bool {
        if didRequestExactTarget(step) {
            return true
        }
        return labelsAreCompatible(requestedLabel, target.label)
    }

    private func didRequestExactTarget(_ step: WorkflowStep) -> Bool {
        if let targetID = step.targetID?.trimmingCharacters(in: .whitespacesAndNewlines), !targetID.isEmpty {
            return true
        }
        return step.targetMark != nil
    }

    private func localPreGroundTarget(
        for step: WorkflowStep,
        label: String,
        targets: [LocalPerceptionTargetCache.SnapshotTarget]
    ) -> LocalPerceptionTargetCache.SnapshotTarget? {
        if let targetID = step.targetID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !targetID.isEmpty,
           let target = targets.first(where: { $0.id == targetID }),
           labelsAreCompatible(label, target.label) {
            return target
        }

        if let targetMark = step.targetMark,
           let target = targets.first(where: { $0.mark == targetMark }),
           labelsAreCompatible(label, target.label) {
            return target
        }

        return targets
            .compactMap { target -> (target: LocalPerceptionTargetCache.SnapshotTarget, score: Double)? in
                guard let score = labelCompatibilityScore(label, target.label) else { return nil }
                return (
                    target,
                    score + sourceScore(target.source) + min(target.confidence, 1.0)
                )
            }
            .max { $0.score < $1.score }?
            .target
    }

    private func labelsAreCompatible(_ requestedLabel: String, _ candidateLabel: String) -> Bool {
        labelCompatibilityScore(requestedLabel, candidateLabel) != nil
    }

    private func labelCompatibilityScore(_ requestedLabel: String, _ candidateLabel: String) -> Double? {
        if normalizedText(requestedLabel) == normalizedText(candidateLabel) {
            return 100
        }

        let requestedWords = normalizedWords(requestedLabel)
        let candidateWords = normalizedWords(candidateLabel)
        guard !requestedWords.isEmpty, !candidateWords.isEmpty else { return nil }

        if requestedWords == candidateWords { return 96 }
        if requestedWords.count == 1,
           candidateWords.count == 1,
           let requested = requestedWords.first,
           let candidate = candidateWords.first {
            if requested == candidate { return 96 }
            return editDistance(requested, candidate) <= 1 ? 68 : nil
        }

        if candidateWords.count > requestedWords.count,
           requestedWords.count == 1,
           let requested = requestedWords.first {
            let unsafeExpansions: Set<String> = ["mode", "modeling", "edit", "layout", "scene"]
            if candidateWords.contains(requested),
               candidateWords.intersection(unsafeExpansions).isEmpty {
                return 58
            }
            return nil
        }

        if requestedWords.isSubset(of: candidateWords)
            || candidateWords.isSubset(of: requestedWords) {
            return 54
        }

        return nil
    }

    private func sourceScore(_ source: String) -> Double {
        source == "ocr" ? 4 : 1
    }

    private func normalizedWords(_ text: String) -> Set<String> {
        let aliases = [
            "taurus": "torus",
            "particles": "particle",
            "properties": "property",
            "checkbox": "",
            "button": "",
            "icon": "",
            "menu": "",
            "submenu": "",
            "field": "",
            "panel": ""
        ]
        let rawWords = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { word -> String in
                let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
                if let alias = aliases[trimmed] { return alias }
                if trimmed.count > 4, trimmed.hasSuffix("s") {
                    return String(trimmed.dropLast())
                }
                return trimmed
            }
            .filter { !$0.isEmpty && $0 != "the" && $0 != "a" && $0 != "an" }
        return Set(rawWords)
    }

    private func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func editDistance(_ firstText: String, _ secondText: String) -> Int {
        let firstCharacters = Array(firstText)
        let secondCharacters = Array(secondText)
        guard !firstCharacters.isEmpty else { return secondCharacters.count }
        guard !secondCharacters.isEmpty else { return firstCharacters.count }

        var previousRow = Array(0...secondCharacters.count)
        var currentRow = Array(repeating: 0, count: secondCharacters.count + 1)

        for firstIndex in 1...firstCharacters.count {
            currentRow[0] = firstIndex
            for secondIndex in 1...secondCharacters.count {
                let substitutionCost = firstCharacters[firstIndex - 1] == secondCharacters[secondIndex - 1] ? 0 : 1
                currentRow[secondIndex] = min(
                    previousRow[secondIndex] + 1,
                    currentRow[secondIndex - 1] + 1,
                    previousRow[secondIndex - 1] + substitutionCost
                )
            }
            previousRow = currentRow
        }

        return previousRow[secondCharacters.count]
    }

    private func repairWorkflowStep(
        failedStepIndex: Int,
        failureMessage: String,
        attemptNumber: Int
    ) async -> TipTourFollowAlongRepairDecision {
        guard autoRepair,
              let apiKey = KeychainStore.claudeAPIKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              steps.indices.contains(failedStepIndex) else {
            return .none
        }

        let failedStep = steps[failedStepIndex]
        let app = normalizedApp(failedStep.app)
        let targetList = await engine.localPerceptionTargets(
            refresh: true,
            reason: "follow-along repair"
        )
        let nearbySteps = Array(steps[failedStepIndex..<min(steps.count, failedStepIndex + 8)])

        do {
            let suggestion = try await aiPlanner.repairStep(
                transcript: plannerInput(from: transcriptText),
                targetAppName: app,
                failedStepIndex: failedStepIndex,
                failedStep: failedStep.workflowStep,
                failureMessage: failureMessage,
                nearbySteps: nearbySteps.map(\.workflowStep),
                visibleTargets: targetList.targets,
                visualHistory: visualHistory,
                attemptNumber: attemptNumber,
                apiKey: apiKey
            )

            PipelineLogStore.shared.record(
                category: "follow_along",
                name: "repair_plan",
                status: "ok",
                message: suggestion.reason,
                metadata: [
                    "failed_step_index": String(failedStepIndex + 1),
                    "strategy": suggestion.strategy.rawValue,
                    "target_count": String(targetList.targets.count),
                    "repair_label": suggestion.step?.label ?? "",
                    "repair_type": suggestion.step?.type.rawValue ?? ""
                ]
            )

            switch suggestion.strategy {
            case .insertBefore:
                guard let workflowStep = suggestion.step else { return .none }
                return .insertBefore(
                    TipTourFollowAlongStep(
                        sourceText: "Repair before step \(failedStepIndex + 1): \(suggestion.reason)",
                        app: app,
                        workflowStep: workflowStep
                    ),
                    reason: suggestion.reason
                )
            case .replace:
                guard let workflowStep = suggestion.step else { return .none }
                return .replace(
                    TipTourFollowAlongStep(
                        sourceText: "Repair step \(failedStepIndex + 1): \(suggestion.reason)",
                        app: app,
                        workflowStep: workflowStep
                    ),
                    reason: suggestion.reason
                )
            case .skip:
                return .skip(reason: suggestion.reason)
            }
        } catch {
            PipelineLogStore.shared.record(
                category: "follow_along",
                name: "repair_plan",
                status: "failed",
                message: error.localizedDescription,
                metadata: [
                    "failed_step_index": String(failedStepIndex + 1),
                    "attempt": String(attemptNumber)
                ]
            )
            appendLog("repair: planner failed")
            return .none
        }
    }

    private func shouldPreGround(_ step: WorkflowStep) -> Bool {
        switch step.type {
        case .click, .rightClick, .doubleClick, .observe:
            return true
        default:
            return false
        }
    }

    private func shouldRefreshAfterTargetlessMenuAction(_ step: WorkflowStep) -> Bool {
        switch step.type {
        case .keyboardShortcut, .pressKey:
            return true
        default:
            return false
        }
    }

    private func workflowStepWithTarget(
        _ step: WorkflowStep,
        target: TipTourEngineGroundedTarget
    ) -> WorkflowStep {
        WorkflowStep(
            id: step.id,
            type: step.type,
            label: target.label,
            targetID: target.targetID,
            targetMark: target.targetMark,
            value: step.value,
            direction: step.direction,
            amount: step.amount,
            by: step.by,
            targetContext: step.targetContext,
            hint: step.hint,
            hintX: step.hintX,
            hintY: step.hintY,
            box2DNormalized: step.box2DNormalized,
            screenNumber: step.screenNumber
        )
    }

    private func repairStep(
        _ step: TipTourFollowAlongStep,
        app: String?
    ) async -> (ok: Bool, message: String?) {
        let targetList = await engine.localPerceptionTargets(
            refresh: true,
            reason: "follow-along local repair"
        )
        let workflowStep = normalizedWorkflowStepForExecution(
            step.workflowStep,
            sourceText: step.sourceText,
            app: app,
            visibleTargets: targetList.targets
        )

        guard canRepairThroughGrounding(workflowStep),
              let label = workflowStep.label,
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (false, "No local repair path for this step type.")
        }

        let repairResult = await engine.planNextAction(
            goal: step.sourceText,
            app: app,
            requestedActionType: workflowStep.type,
            requestedTargetLabel: label,
            execute: true,
            allowScreenshotPlanning: true,
            validateStateChange: true
        )
        return (repairResult.ok, repairResult.message ?? repairResult.reason)
    }

    private func canRepairThroughGrounding(_ step: WorkflowStep) -> Bool {
        switch step.type {
        case .click, .rightClick, .doubleClick, .observe:
            return true
        default:
            return false
        }
    }

    private func normalizedApp(_ stepApp: String?) -> String? {
        let stepApp = stepApp?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stepApp.isEmpty { return stepApp }
        let defaultApp = targetApp.trimmingCharacters(in: .whitespacesAndNewlines)
        return defaultApp.isEmpty ? nil : defaultApp
    }

    private func plannerInput(from transcript: String) -> String {
        let skillInstructions = activeSkillInstructions(for: targetApp)
        let trimmedSummary = enrichmentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections = [transcript]

        if !skillInstructions.isEmpty {
            sections.append(
                """
                Active app skill instructions:
                \(skillInstructions)
                """
            )
        }

        if !trimmedSummary.isEmpty {
            sections.append(
                """
                Video/frame context from sampled YouTube frames:
                \(trimmedSummary)
                """
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private func activeSkillInstructions(for app: String) -> String {
        guard let skill = MarkdownAppSkillRegistry.shared.skill(applicationName: app),
              !skill.runtimeHints.plannerInstructions.isEmpty else {
            return ""
        }

        return """
        Active app skill: \(skill.name)
        \(skill.runtimeHints.plannerInstructions.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private func resetTraceRun() {
        currentTraceRunID = traceStore.makeRunID()
        latestTracePath = ""
        visualHistory = []
        lastDistinctPreState = nil
    }

    private func stateActionMatchedState(
        for state: TipTourFollowAlongTraceStore.StateSnapshot
    ) -> TipTourFollowAlongTraceStore.StateSnapshot {
        guard let screenshotHash = state.screenshotHash, !screenshotHash.isEmpty else {
            lastDistinctPreState = state
            return state
        }

        if let lastDistinctPreState,
           state.screenChangedSinceLastSnapshot == false {
            return lastDistinctPreState
        }

        if lastDistinctPreState?.screenshotHash != screenshotHash {
            lastDistinctPreState = state
        }
        return lastDistinctPreState ?? state
    }

    private func updateVisualHistory(
        visualContext: TipTourEngineVisualContextSnapshot,
        targets: [LocalPerceptionTargetCache.SnapshotTarget]
    ) {
        let item = TipTourFollowAlongVisualHistoryItem(
            visualContext: visualContext,
            targets: targets
        )

        if item.hasScreenshots {
            if visualHistory.last?.screenshotHash != item.screenshotHash {
                visualHistory.append(item)
            }
        } else if visualHistory.isEmpty {
            visualHistory.append(item)
        }
        visualHistory = Array(visualHistory.suffix(3))
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logLines.append("\(formatter.string(from: Date())) \(line)")
        if logLines.count > 80 {
            logLines.removeFirst(logLines.count - 80)
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private enum TipTourFollowAlongRepairDecision {
    case none
    case insertBefore(TipTourFollowAlongStep, reason: String)
    case replace(TipTourFollowAlongStep, reason: String)
    case skip(reason: String)
}

private struct TipTourFollowAlongRepairSuggestion {
    enum Strategy: String {
        case insertBefore = "insert_before"
        case replace
        case skip
    }

    let strategy: Strategy
    let reason: String
    let step: WorkflowStep?
}

private enum TipTourFollowAlongScriptParser {
    static func steps(from plan: WorkflowPlan, fallbackApp: String) -> [TipTourFollowAlongStep] {
        plan.steps.enumerated().map { index, step in
            TipTourFollowAlongStep(
                sourceText: step.hint.isEmpty ? "Step \(index + 1)" : step.hint,
                app: plan.app ?? (fallbackApp.isEmpty ? nil : fallbackApp),
                workflowStep: stepWithIDIfNeeded(step, index: index)
            )
        }
    }

    static func steps(fromTranscript transcript: String, defaultApp: String) -> [TipTourFollowAlongStep] {
        instructionLines(from: transcript)
            .prefix(80)
            .enumerated()
            .compactMap { index, instruction in
                workflowStep(from: instruction, index: index, defaultApp: defaultApp).map { workflowStep in
                    TipTourFollowAlongStep(
                        sourceText: instruction,
                        app: defaultApp.isEmpty ? nil : defaultApp,
                        workflowStep: workflowStep
                    )
                }
            }
    }

    private static func workflowStep(
        from instruction: String,
        index: Int,
        defaultApp: String
    ) -> WorkflowStep? {
        let trimmed = stripLeadingTimestamp(instruction)
        let lower = trimmed.lowercased()

        if let appName = appLaunchTarget(in: trimmed) {
            return step(
                index: index,
                type: .openApp,
                label: titleCase(appName),
                value: nil,
                hint: "Open \(titleCase(appName))"
            )
        }

        if let url = firstURL(in: trimmed), lower.contains("open") || lower.contains("go to") {
            return step(
                index: index,
                type: .openURL,
                label: url,
                value: url,
                hint: "Open \(url)"
            )
        }

        if let shortcut = shortcut(in: trimmed) {
            return step(
                index: index,
                type: .keyboardShortcut,
                label: shortcut,
                value: nil,
                hint: "Press \(shortcut)"
            )
        }

        if let key = singleKeyPress(in: trimmed) {
            return step(
                index: index,
                type: .pressKey,
                label: key,
                value: nil,
                hint: "Press \(key)"
            )
        }

        if let typedText = textPayload(in: trimmed) {
            return step(
                index: index,
                type: .type,
                label: nil,
                value: typedText,
                hint: "Type \(typedText)"
            )
        }

        if let direction = scrollDirection(in: lower) {
            return WorkflowStep(
                id: "follow_step_\(index + 1)",
                type: .scroll,
                label: direction,
                targetID: nil,
                targetMark: nil,
                value: nil,
                direction: direction,
                amount: nil,
                by: nil,
                targetContext: nil,
                hint: "Scroll \(direction)",
                hintX: nil,
                hintY: nil,
                box2DNormalized: nil,
                screenNumber: nil
            )
        }

        if let label = clickTarget(in: trimmed) {
            return step(
                index: index,
                type: .click,
                label: label,
                value: nil,
                hint: "Click \(label)"
            )
        }

        if lower.contains("look at") || lower.contains("notice") || lower.contains("verify") || lower.contains("wait") {
            return step(
                index: index,
                type: .observe,
                label: nil,
                value: nil,
                hint: trimmed
            )
        }

        return nil
    }

    private static func step(
        index: Int,
        type: WorkflowStep.StepType,
        label: String?,
        value: String?,
        hint: String
    ) -> WorkflowStep {
        WorkflowStep(
            id: "follow_step_\(index + 1)",
            type: type,
            label: label,
            targetID: nil,
            targetMark: nil,
            value: value,
            direction: nil,
            amount: nil,
            by: nil,
            targetContext: nil,
            hint: hint,
            hintX: nil,
            hintY: nil,
            box2DNormalized: nil,
            screenNumber: nil
        )
    }

    private static func stepWithIDIfNeeded(_ step: WorkflowStep, index: Int) -> WorkflowStep {
        guard step.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return step
        }
        return WorkflowStep(
            id: "follow_step_\(index + 1)",
            type: step.type,
            label: step.label,
            targetID: step.targetID,
            targetMark: step.targetMark,
            value: step.value,
            direction: step.direction,
            amount: step.amount,
            by: step.by,
            targetContext: step.targetContext,
            hint: step.hint,
            hintX: step.hintX,
            hintY: step.hintY,
            box2DNormalized: step.box2DNormalized,
            screenNumber: step.screenNumber
        )
    }

    private static func instructionLines(from transcript: String) -> [String] {
        transcript
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: CharacterSet.newlines)
            .flatMap { line -> [String] in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return [] }
                if trimmed.count > 160 {
                    return trimmed
                        .components(separatedBy: ". ")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
                return [trimmed]
            }
            .filter { line in
                let lower = line.lowercased()
                return !["um", "uh", "okay", "so", "now"].contains(lower)
            }
    }

    private static func stripLeadingTimestamp(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*(\[\d{1,2}:\d{2}(?::\d{2})?\]|\d{1,2}:\d{2}(?::\d{2})?)\s*[-–—:]?\s*"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capture(after prefixes: [String], in lower: String, original: String) -> String? {
        for prefix in prefixes where lower.hasPrefix(prefix) {
            let start = original.index(original.startIndex, offsetBy: prefix.count)
            let captured = original[start...]
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            return captured.isEmpty ? nil : String(captured)
        }
        return nil
    }

    private static func appLaunchTarget(in text: String) -> String? {
        let lower = text.lowercased()
        guard let target = capture(
            after: ["open the ", "open ", "launch the ", "launch "],
            in: lower,
            original: text
        ) else {
            return nil
        }

        let targetLower = target.lowercased()
        if targetLower.contains("menu") || targetLower.contains("button") || targetLower.contains("tab") || targetLower.contains("panel") {
            return nil
        }
        if lower.hasPrefix("launch ") || lower.hasPrefix("launch the ") {
            return target
        }
        let knownApps: Set<String> = [
            "blender", "xcode", "notes", "safari", "chrome", "google chrome",
            "finder", "preview", "photoshop", "figma", "cursor", "visual studio code",
            "vs code", "terminal"
        ]
        if knownApps.contains(targetLower.trimmingCharacters(in: CharacterSet(charactersIn: " ."))) {
            return target
        }
        if targetLower.contains("app") || targetLower.contains("application") {
            return target
                .replacingOccurrences(of: " app", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: " application", with: "", options: .caseInsensitive)
        }
        return nil
    }

    private static func firstURL(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?
            .firstMatch(in: text, options: [], range: range)?
            .url?
            .absoluteString
    }

    private static func shortcut(in text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "Command", with: "Cmd", options: .caseInsensitive)
            .replacingOccurrences(of: "Control", with: "Ctrl", options: .caseInsensitive)
            .replacingOccurrences(of: "Option", with: "Option", options: .caseInsensitive)
            .replacingOccurrences(of: "Shift", with: "Shift", options: .caseInsensitive)

        let pattern = #"(Cmd|Ctrl|Control|Option|Alt|Shift)(\s*\+\s*(Cmd|Ctrl|Control|Option|Alt|Shift|[A-Za-z0-9/]+))+"#
        guard let range = normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return normalized[range]
            .components(separatedBy: "+")
            .map { part in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                switch trimmed.lowercased() {
                case "command": return "Cmd"
                case "control": return "Ctrl"
                case "alt": return "Option"
                default:
                    if trimmed.count == 1 { return trimmed.uppercased() }
                    return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
                }
            }
            .joined(separator: "+")
    }

    private static func singleKeyPress(in text: String) -> String? {
        let lower = text.lowercased()
        let keyNames = [
            "return": "Return",
            "enter": "Return",
            "escape": "Escape",
            "esc": "Escape",
            "delete": "Delete",
            "backspace": "Delete",
            "tab": "Tab",
            "space": "Space"
        ]
        for (word, key) in keyNames where lower.contains("press \(word)") || lower.contains("hit \(word)") {
            return key
        }
        if let range = lower.range(of: #"press\s+['"]?([a-z0-9])['"]?"#, options: .regularExpression) {
            let matched = String(lower[range])
            return matched.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .last(where: { !$0.isEmpty })?
                .uppercased()
        }
        return nil
    }

    private static func textPayload(in text: String) -> String? {
        let lower = text.lowercased()
        guard lower.hasPrefix("type ") || lower.hasPrefix("write ") || lower.hasPrefix("enter ") || lower.hasPrefix("paste ") else {
            return nil
        }
        let prefixes = ["type ", "write ", "enter ", "paste "]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            let start = text.index(text.startIndex, offsetBy: prefix.count)
            let payload = String(text[start...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            return payload.isEmpty ? nil : payload
        }
        return nil
    }

    private static func scrollDirection(in lower: String) -> String? {
        if lower.contains("scroll down") { return "down" }
        if lower.contains("scroll up") { return "up" }
        if lower.contains("scroll left") { return "left" }
        if lower.contains("scroll right") { return "right" }
        return nil
    }

    private static func clickTarget(in text: String) -> String? {
        let lower = text.lowercased()
        if lower.hasPrefix("open "), lower.contains("menu") {
            let target = text
                .replacingOccurrences(of: #"(?i)^open\s+(the\s+)?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\s+submenu\.?$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\s+menu\.?$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " .\"'"))
            return target.isEmpty ? nil : target
        }

        let verbs = ["click on ", "click ", "select ", "choose ", "tap ", "open the menu ", "open menu "]
        for verb in verbs {
            guard let range = lower.range(of: verb) else { continue }
            let startOffset = lower.distance(from: lower.startIndex, to: range.upperBound)
            let start = text.index(text.startIndex, offsetBy: startOffset)
            let target = text[start...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " .\"'"))
            return target.isEmpty ? nil : String(target)
        }
        return nil
    }

    private static func titleCase(_ text: String) -> String {
        text
            .split(separator: " ")
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }
}

private struct TipTourFollowAlongAIPlannerClient {
    private struct PlannerTarget: Encodable {
        let id: String
        let mark: Int
        let label: String
        let source: String
        let confidence: Double
        let box2D: [Int]

        init(_ target: LocalPerceptionTargetCache.SnapshotTarget) {
            id = target.id
            mark = target.mark
            label = target.label
            source = target.source
            confidence = target.confidence
            box2D = target.normalizedBox2D
        }
    }

    private struct MessagesRequest: Encodable {
        let model: String
        let maxTokens: Int
        let system: String
        let messages: [Message]

        enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case system
            case messages
        }
    }

    private struct Message: Encodable {
        let role: String
        let content: [ContentBlock]
    }

    private struct ContentBlock: Encodable {
        let type: String
        let text: String?
        let source: ImageSource?

        static func text(_ text: String) -> ContentBlock {
            ContentBlock(type: "text", text: text, source: nil)
        }

        static func image(mediaType: String, base64Data: String) -> ContentBlock {
            ContentBlock(
                type: "image",
                text: nil,
                source: ImageSource(mediaType: mediaType, data: base64Data)
            )
        }

        private init(type: String, text: String?, source: ImageSource?) {
            self.type = type
            self.text = text
            self.source = source
        }
    }

    private struct ImageSource: Encodable {
        let type = "base64"
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }

    private struct MessagesResponse: Decodable {
        let content: [ResponseContentBlock]
    }

    private struct ResponseContentBlock: Decodable {
        let type: String
        let text: String?
    }

    private struct RepairPayload: Decodable {
        let strategy: String?
        let reason: String?
        let step: RepairStep?

        struct RepairStep: Decodable {
            let id: String?
            let type: String?
            let action: String?
            let label: String?
            let target: String?
            let element: String?
            let targetLabel: String?
            let target_label: String?
            let targetID: String?
            let target_id: String?
            let targetMark: Int?
            let target_mark: Int?
            let value: String?
            let text: String?
            let direction: String?
            let amount: Int?
            let by: String?
            let hint: String?
            let description: String?
            let targetContext: String?
            let target_context: String?

            func workflowStep() -> WorkflowStep {
                WorkflowStep(
                    id: id ?? "repair_step",
                    type: WorkflowStep.StepType.normalized(from: type ?? action),
                    label: label ?? target ?? element ?? targetLabel ?? target_label,
                    targetID: targetID ?? target_id,
                    targetMark: targetMark ?? target_mark,
                    value: value ?? text,
                    direction: direction,
                    amount: amount,
                    by: by,
                    targetContext: WorkflowStep.TargetContext.normalized(from: targetContext ?? target_context),
                    hint: hint ?? description ?? "",
                    hintX: nil,
                    hintY: nil,
                    box2DNormalized: nil,
                    screenNumber: nil
                )
            }
        }

        func suggestion() -> TipTourFollowAlongRepairSuggestion {
            let normalizedStrategy = (strategy ?? "replace")
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
            let parsedStrategy: TipTourFollowAlongRepairSuggestion.Strategy
            switch normalizedStrategy {
            case "insert", "insert_before", "insertbefore", "setup":
                parsedStrategy = .insertBefore
            case "skip", "cannot_repair", "stop":
                parsedStrategy = .skip
            default:
                parsedStrategy = .replace
            }

            return TipTourFollowAlongRepairSuggestion(
                strategy: parsedStrategy,
                reason: reason ?? "Repair planner suggested a new next action.",
                step: step?.workflowStep()
            )
        }
    }

    func planSteps(transcript: String, targetAppName: String?, apiKey: String) async throws -> WorkflowPlan {
        let requestBody = MessagesRequest(
            model: "claude-sonnet-4-5-20250929",
            maxTokens: 5000,
            system: Self.systemPrompt,
            messages: [
                Message(
                    role: "user",
                    content: [
                        ContentBlock.text(
                            """
                            Target app:
                            \(targetAppName ?? "unknown")

                            Tutorial transcript or script:
                            \(transcript)

                            Convert this into TipTour follow-along actions.
                            """
                        )
                    ]
                )
            ]
        )

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        try ProviderRequestDiagnostics.validateHTTPResponse(
            response,
            data: data,
            serviceName: "Claude follow-along planner request",
            errorDomain: "TipTourFollowAlongAIPlannerClient"
        )

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        let text = decoded.content.compactMap(\.text).joined(separator: "\n")
        guard let plan = WorkflowPlan.parse(from: text) else {
            throw NSError(
                domain: "TipTourFollowAlongAIPlannerClient",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Claude did not return a valid follow-along plan."]
            )
        }
        return plan
    }

    func repairStep(
        transcript: String,
        targetAppName: String?,
        failedStepIndex: Int,
        failedStep: WorkflowStep,
        failureMessage: String,
        nearbySteps: [WorkflowStep],
        visibleTargets: [LocalPerceptionTargetCache.SnapshotTarget],
        visualHistory: [TipTourFollowAlongVisualHistoryItem] = [],
        attemptNumber: Int,
        apiKey: String
    ) async throws -> TipTourFollowAlongRepairSuggestion {
        let content = [
            ContentBlock.text(
                repairPrompt(
                    transcript: transcript,
                    targetAppName: targetAppName,
                    failedStepIndex: failedStepIndex,
                    failedStep: failedStep,
                    failureMessage: failureMessage,
                    nearbySteps: nearbySteps,
                    visibleTargets: visibleTargets,
                    attemptNumber: attemptNumber
                )
            )
        ] + visualHistoryContentBlocks(from: visualHistory)

        let requestBody = MessagesRequest(
            model: "claude-sonnet-4-5-20250929",
            maxTokens: 1800,
            system: Self.repairSystemPrompt,
            messages: [
                Message(
                    role: "user",
                    content: content
                )
            ]
        )

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        try ProviderRequestDiagnostics.validateHTTPResponse(
            response,
            data: data,
            serviceName: "Claude follow-along repair request",
            errorDomain: "TipTourFollowAlongAIPlannerClient"
        )

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        let text = decoded.content.compactMap(\.text).joined(separator: "\n")
        guard let jsonText = extractFirstJSONObject(from: text),
              let jsonData = jsonText.data(using: .utf8) else {
            throw NSError(
                domain: "TipTourFollowAlongAIPlannerClient",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Claude did not return a valid repair JSON object."]
            )
        }
        let payload = try JSONDecoder().decode(RepairPayload.self, from: jsonData)
        return payload.suggestion()
    }

    private func repairPrompt(
        transcript: String,
        targetAppName: String?,
        failedStepIndex: Int,
        failedStep: WorkflowStep,
        failureMessage: String,
        nearbySteps: [WorkflowStep],
        visibleTargets: [LocalPerceptionTargetCache.SnapshotTarget],
        attemptNumber: Int
    ) -> String {
        let targetJSON = encodeJSON(
            visibleTargets
                .filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(120)
                .map(PlannerTarget.init)
        )
        let failedStepJSON = encodeJSON(failedStep)
        let nearbyStepsJSON = encodeJSON(nearbySteps)

        return """
        Target app:
        \(targetAppName ?? "unknown")

        Repair attempt:
        \(attemptNumber)

        Failure:
        Step \(failedStepIndex + 1) failed with message:
        \(failureMessage)

        Failed step JSON:
        \(failedStepJSON)

        Upcoming draft steps:
        \(nearbyStepsJSON)

        Current visible local targets:
        \(targetJSON)

        Original transcript:
        \(transcript)

        Return the one best repair action now.
        """
    }

    private func visualHistoryContentBlocks(
        from visualHistory: [TipTourFollowAlongVisualHistoryItem]
    ) -> [ContentBlock] {
        visualHistory.suffix(3).flatMap { item -> [ContentBlock] in
            var blocks: [ContentBlock] = [
                .text(
                    """
                    Visual state before/around the failed action:
                    \(item.promptSummary)
                    """
                )
            ]

            if let screenshot = item.screenshots.first,
               let image = imagePayload(from: screenshot.dataURL, fallbackMediaType: screenshot.mediaType) {
                blocks.append(.image(mediaType: image.mediaType, base64Data: image.base64Data))
            }
            return blocks
        }
    }

    private func imagePayload(
        from dataURL: String,
        fallbackMediaType: String
    ) -> (mediaType: String, base64Data: String)? {
        let marker = ";base64,"
        guard let range = dataURL.range(of: marker) else {
            let trimmed = dataURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (fallbackMediaType, trimmed)
        }

        let header = String(dataURL[..<range.lowerBound])
        let mediaType = header.replacingOccurrences(of: "data:", with: "")
        let payload = String(dataURL[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }
        return (mediaType.isEmpty ? fallbackMediaType : mediaType, payload)
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func extractFirstJSONObject(from text: String) -> String? {
        var depth = 0
        var startIndex: String.Index?
        for index in text.indices {
            let character = text[index]
            if character == "{" {
                if depth == 0 { startIndex = index }
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0, let startIndex {
                    return String(text[startIndex...index])
                }
            }
        }
        return nil
    }

    private static let systemPrompt = """
    You convert tutorial transcripts into TipTour desktop automation steps.

    Return only JSON. No Markdown and no prose.

    Schema:
    {
      "goal": "short tutorial goal",
      "app": "target app name if known",
      "steps": [
        {
          "id": "step_1",
          "type": "click | rightClick | doubleClick | openApp | openURL | keyboardShortcut | pressKey | type | setValue | scroll | observe",
          "label": "visible target label, app name, key, shortcut, or short target name",
          "value": "text or URL when needed",
          "direction": "up | down | left | right for scroll",
          "targetContext": "visibleElement | currentHighlight | currentSelection | focusedElement",
          "hint": "short imperative action"
        }
      ]
    }

    Rules:
    - Keep only concrete actions that the presenter tells the viewer to do.
    - If the user message includes Active app skill instructions, follow those app-specific rules over generic transcript wording.
    - If the user message includes Video/frame context, use it to correct transcript mistakes, prefer visible labels, and identify manual visual checkpoints.
    - Skip filler, narration, explanations, and non-action commentary.
    - Split multi-action instructions into one action per step.
    - For menus, emit only the next visible click, then the submenu click as another step.
    - Use literal shortcut labels like Cmd+S, Cmd+Shift+F, Shift+A.
    - Use pressKey for one physical key like Return, Escape, X, Z, S, or Tab.
    - Use type only when the tutorial explicitly says to type text or a numeric value.
    - Use setValue only if the exact field label is likely visible.
    - Avoid observe for instructions that imply action. "select", "open", "enable", "set", "add", "click", "choose", "convert", "press", "scale", and "scroll" should be executable steps.
    - Use observe only for genuinely manual or visual checkpoints such as "pause when happy", "adjust faces as needed", or "connect node sockets" where one safe desktop action is not knowable yet.
    - Limit to the first 60 high-confidence steps.
    """

    private static let repairSystemPrompt = """
    You are TipTour's runtime repair planner. A generated tutorial step failed while TipTour was running it on the live desktop. Use the current visible local targets and the failed step to choose exactly one repair action.

    Return only JSON. No Markdown and no prose.

    Schema:
    {
      "strategy": "insert_before | replace | skip",
      "reason": "short explanation",
      "step": {
        "id": "repair_step",
        "type": "click | rightClick | doubleClick | openApp | openURL | keyboardShortcut | pressKey | type | setValue | scroll | observe",
        "label": "visible target label, app name, key, shortcut, or short target name",
        "target_id": "exact id from current visible targets when applicable",
        "target_mark": 12,
        "value": "text or URL when needed",
        "direction": "up | down | left | right for scroll",
        "targetContext": "visibleElement | currentHighlight | currentSelection | focusedElement",
        "hint": "short imperative action"
      }
    }

    Strategy rules:
    - Use "insert_before" when the failed step is still correct but a prerequisite UI state is missing. Example: failed Mesh because the Add menu is closed, so insert click Add.
    - Use "replace" when the failed step itself is wrong for the current screen. Example: the transcript target is an alias or typo, but an equivalent visible label is present.
    - Use "skip" only for non-action checkpoints that cannot be safely automated from visible context.
    - Prefer exact target_id and target_mark from Current visible local targets for visible clicks.
    - Do not guess raw coordinates. If no target is visible, choose a setup action that is visible, or skip with a clear reason.
    - If the prompt includes Active app skill instructions, follow those app-specific menu paths, aliases, and modal input rules.
    - If the failed step type is observe, do not return another observe step. Return click, keyboardShortcut, pressKey, type, setValue, scroll, openApp, openURL, or skip.
    - Treat observe hints with action verbs as repairable actions. Examples: "Select the icing" should become a click on the visible icing/object target; "Open particle properties" should become a click on the visible particle properties icon/label; "Enable Mesh checkbox" should become a click if the checkbox/label is visible.
    - Return exactly one step unless strategy is "skip"; skip may omit step.
    """
}

private enum TipTourYouTubeTranscriptLoader {
    struct Result: Sendable {
        let transcript: String
        let source: String
    }

    static func loadTranscript(from urlString: String) async throws -> Result {
        guard URL(string: urlString) != nil else {
            throw failure("Enter a valid YouTube URL.")
        }
        guard let ytDlp = executable(named: "yt-dlp") else {
            throw failure("yt-dlp is not installed. Install with: brew install yt-dlp ffmpeg")
        }

        let directory = try workingDirectory()
        let outputTemplate = directory.appendingPathComponent("video.%(ext)s").path

        _ = try? await TipTourCommandRunner.run(
            executablePath: ytDlp,
            arguments: [
                "--no-playlist",
                "--write-auto-subs",
                "--write-subs",
                "--sub-langs", "en.*,en",
                "--sub-format", "vtt",
                "--skip-download",
                "-o", outputTemplate,
                urlString
            ],
            timeoutSeconds: 180
        )

        if let transcript = try transcriptFromVTT(in: directory), !transcript.isEmpty {
            return Result(transcript: transcript, source: "YouTube captions")
        }

        let audioTemplate = directory.appendingPathComponent("audio.%(ext)s").path
        _ = try await TipTourCommandRunner.run(
            executablePath: ytDlp,
            arguments: [
                "--no-playlist",
                "-f", "bestaudio",
                "--extract-audio",
                "--audio-format", "wav",
                "-o", audioTemplate,
                urlString
            ],
            timeoutSeconds: 900
        )

        guard let audioPath = try firstFile(in: directory, extensions: ["wav", "m4a", "mp3", "opus", "webm"]) else {
            throw failure("yt-dlp finished but no audio file was found.")
        }

        let whisperDirectory = directory.appendingPathComponent("whisperx", isDirectory: true)
        try FileManager.default.createDirectory(at: whisperDirectory, withIntermediateDirectories: true)

        if let whisperx = executable(named: "whisperx") {
            _ = try await runWhisperX(
                executablePath: whisperx,
                argumentsPrefix: [],
                audioPath: audioPath,
                outputDirectory: whisperDirectory
            )
        } else if let uvx = executable(named: "uvx") {
            _ = try await runWhisperX(
                executablePath: uvx,
                argumentsPrefix: ["whisperx"],
                audioPath: audioPath,
                outputDirectory: whisperDirectory
            )
        } else {
            throw failure("No captions found and WhisperX is not installed. Install with: pip install whisperx, pipx install whisperx, or brew install uv && uvx whisperx ...")
        }

        guard let transcript = try transcriptFromWhisperJSON(in: whisperDirectory), !transcript.isEmpty else {
            throw failure("WhisperX finished but no transcript JSON was found.")
        }
        return Result(transcript: transcript, source: "WhisperX")
    }

    private static func runWhisperX(
        executablePath: String,
        argumentsPrefix: [String],
        audioPath: URL,
        outputDirectory: URL
    ) async throws -> TipTourCommandRunner.Result {
        try await TipTourCommandRunner.run(
            executablePath: executablePath,
            arguments: argumentsPrefix + [
                audioPath.path,
                "--model", "small",
                "--device", "cpu",
                "--compute_type", "int8",
                "--output_format", "json",
                "--output_dir", outputDirectory.path
            ],
            timeoutSeconds: 3_600
        )
    }

    private static func workingDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("TipTour/follow-along", isDirectory: true)
        .appendingPathComponent("run_\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func transcriptFromVTT(in directory: URL) throws -> String? {
        guard let file = try firstFile(in: directory, extensions: ["vtt"]) else { return nil }
        let text = try String(contentsOf: file, encoding: .utf8)
        var seen = Set<String>()
        let lines = text
            .components(separatedBy: CharacterSet.newlines)
            .map(cleanVTTLine)
            .filter { line in
                guard !line.isEmpty else { return false }
                if seen.contains(line) { return false }
                seen.insert(line)
                return true
            }
        return lines.joined(separator: "\n")
    }

    private static func cleanVTTLine(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return "" }
        if line == "WEBVTT" || line.hasPrefix("Kind:") || line.hasPrefix("Language:") || line.hasPrefix("NOTE") {
            return ""
        }
        if line.contains("-->") { return "" }
        if line.range(of: #"^\d+$"#, options: .regularExpression) != nil { return "" }
        line = line.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: "&nbsp;", with: " ")
        line = line.replacingOccurrences(of: "&amp;", with: "&")
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct WhisperJSON: Decodable {
        let segments: [Segment]

        struct Segment: Decodable {
            let start: Double?
            let end: Double?
            let text: String?
        }
    }

    private static func transcriptFromWhisperJSON(in directory: URL) throws -> String? {
        guard let file = try firstFile(in: directory, extensions: ["json"]) else { return nil }
        let data = try Data(contentsOf: file)
        let decoded = try JSONDecoder().decode(WhisperJSON.self, from: data)
        return decoded.segments
            .compactMap { segment in
                guard let text = segment.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    return nil
                }
                if let start = segment.start {
                    return "[\(timestamp(start))] \(text)"
                }
                return text
            }
            .joined(separator: "\n")
    }

    private static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func firstFile(in directory: URL, extensions: Set<String>) throws -> URL? {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { extensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return files.first
    }

    private static func firstFile(in directory: URL, extensions: [String]) throws -> URL? {
        try firstFile(in: directory, extensions: Set(extensions.map { $0.lowercased() }))
    }

    private static func executable(named name: String) -> String? {
        var searchPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        searchPaths.insert(contentsOf: envPaths, at: 0)

        var checked = Set<String>()
        for path in searchPaths {
            let executablePath = URL(fileURLWithPath: path)
                .appendingPathComponent(name)
                .path
            guard !checked.contains(executablePath) else { continue }
            checked.insert(executablePath)
            if FileManager.default.isExecutableFile(atPath: executablePath) {
                return executablePath
            }
        }
        return nil
    }

    private static func failure(_ message: String) -> NSError {
        NSError(
            domain: "TipTourYouTubeTranscriptLoader",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private enum TipTourCommandRunner {
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func run(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var environment = ProcessInfo.processInfo.environment
            let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            let localUserBin = "\(NSHomeDirectory())/.local/bin"
            environment["PATH"] = "\(environment["PATH"] ?? ""):\(localUserBin):\(extraPath)"
            process.environment = environment

            try process.run()
            let startDate = Date()
            while process.isRunning {
                if Date().timeIntervalSince(startDate) > timeoutSeconds {
                    process.terminate()
                    throw NSError(
                        domain: "TipTourCommandRunner",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: executablePath).lastPathComponent) timed out."]
                    )
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw NSError(
                    domain: "TipTourCommandRunner",
                    code: Int(process.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: executablePath).lastPathComponent) failed: \(stderr.isEmpty ? stdout : stderr)"
                    ]
                )
            }

            return Result(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }
        .value
    }
}
