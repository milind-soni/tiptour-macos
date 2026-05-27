import AppKit
import Combine
import SwiftUI

@MainActor
final class TipTourSettingsWindowManager {
    private weak var companionManager: CompanionManager?
    private var window: NSWindow?
    private let initialWindowSize = NSSize(width: 760, height: 560)
    private let minimumWindowSize = NSSize(width: 700, height: 500)

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
        let settingsView = TipTourSettingsView(companionManager: companionManager)
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(origin: .zero, size: initialWindowSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.sizingOptions = [.intrinsicContentSize]

        let settingsWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "TipTour Settings"
        settingsWindow.titleVisibility = .hidden
        settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.backgroundColor = .clear
        settingsWindow.isOpaque = false
        settingsWindow.hasShadow = true
        settingsWindow.minSize = minimumWindowSize
        settingsWindow.contentMinSize = minimumWindowSize
        settingsWindow.setFrameAutosaveName("TipTourSettingsWindow")
        settingsWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        settingsWindow.contentView = hostingView

        window = settingsWindow
    }
}

@MainActor
final class TipTourLogsWindowManager {
    private var window: NSWindow?
    private let initialWindowSize = NSSize(width: 920, height: 620)
    private let minimumWindowSize = NSSize(width: 760, height: 460)

    func show() {
        PipelineLogStore.shared.reloadFromDisk()

        if window == nil {
            createWindow()
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() {
        let hostingView = NSHostingView(rootView: TipTourLogsWindowView())
        hostingView.frame = NSRect(origin: .zero, size: initialWindowSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.sizingOptions = [.intrinsicContentSize]

        let logsWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        logsWindow.title = "TipTour Logs"
        logsWindow.titleVisibility = .hidden
        logsWindow.titlebarAppearsTransparent = true
        logsWindow.isReleasedWhenClosed = false
        logsWindow.backgroundColor = .clear
        logsWindow.isOpaque = false
        logsWindow.hasShadow = true
        logsWindow.minSize = minimumWindowSize
        logsWindow.contentMinSize = minimumWindowSize
        logsWindow.setFrameAutosaveName("TipTourLogsWindow")
        logsWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        logsWindow.contentView = hostingView

        window = logsWindow
    }
}

struct PipelineLogEvent: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: String
    let category: String
    let name: String
    let status: String
    let message: String?
    let metadata: [String: String]

    var jsonLine: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    var clipboardSummary: String {
        var lines = [
            "\(timestamp) \(status.uppercased()) \(category).\(name)"
        ]
        if let message, !message.isEmpty {
            lines.append(message)
        }
        if !metadata.isEmpty {
            lines.append(metadataLine(includingCommonContext: true))
        }
        return lines.joined(separator: "\n")
    }

    var terminalBlock: String {
        var usedKeys = Set<String>()
        var lines = [
            "\(timestamp) [\(status.uppercased())] \(category).\(name)"
        ]

        if let message, !message.isEmpty {
            lines.append("  msg: \(message)")
        }

        appendSummaryLine(
            title: "trace",
            pairs: [
                ("id", metadataValue(TipTourActionTrace.metadataKey, usedKeys: &usedKeys))
            ],
            to: &lines
        )

        appendSummaryLine(
            title: "task",
            pairs: [
                ("goal", metadataValue("goal", usedKeys: &usedKeys)),
                ("app", firstMetadataValue(["app", "target_app", "active_app"], usedKeys: &usedKeys)),
                ("action", metadataValue("action_type", usedKeys: &usedKeys))
            ],
            to: &lines
        )

        appendSummaryLine(
            title: "step",
            pairs: [
                ("index", metadataValue("active_step_index", usedKeys: &usedKeys)),
                ("count", metadataValue("step_count", usedKeys: &usedKeys)),
                ("id", metadataValue("step_id", usedKeys: &usedKeys))
            ],
            to: &lines
        )

        appendSummaryLine(
            title: "target",
            pairs: [
                ("label", firstMetadataValue(["resolved_label", "target_label", "label"], usedKeys: &usedKeys)),
                ("mark", metadataValue("target_mark", usedKeys: &usedKeys)),
                ("id", metadataValue("target_id", usedKeys: &usedKeys)),
                ("source", firstMetadataValue(["resolution_source", "source", "matched_source"], usedKeys: &usedKeys))
            ],
            to: &lines
        )

        appendSummaryLine(
            title: "geometry",
            pairs: [
                ("point", pointSummary(usedKeys: &usedKeys)),
                ("rect", metadataValue("resolved_rect", usedKeys: &usedKeys)),
                ("box", metadataValue("box_2d", usedKeys: &usedKeys))
            ],
            to: &lines
        )

        appendSummaryLine(
            title: "result",
            pairs: [
                ("reason", metadataValue("reason", usedKeys: &usedKeys)),
                ("changed", metadataValue("state_changed", usedKeys: &usedKeys)),
                ("accepted", metadataValue("accepted_steps", usedKeys: &usedKeys)),
                ("ignored", metadataValue("ignored_steps", usedKeys: &usedKeys)),
                ("targets", firstMetadataValue(["latest_target_count", "target_count", "candidate_count"], usedKeys: &usedKeys))
            ],
            to: &lines
        )

        appendSummaryLine(
            title: "context",
            pairs: [
                ("frontmost", metadataValue("frontmost_app", usedKeys: &usedKeys)),
                ("pid", metadataValue("frontmost_pid", usedKeys: &usedKeys)),
                ("bundle", metadataValue("frontmost_bundle", usedKeys: &usedKeys))
            ],
            to: &lines
        )

        let remainingMetadata = metadata
            .filter { !usedKeys.contains($0.key) && !Self.prettyHiddenMetadataKeys.contains($0.key) }
            .sorted { $0.key < $1.key }

        if !remainingMetadata.isEmpty {
            lines.append("  meta:")
            lines.append(contentsOf: remainingMetadata.map { "    \($0.key): \($0.value)" })
        }

        return lines.joined(separator: "\n")
    }

    func metadataLine(includingCommonContext: Bool) -> String {
        metadata
            .filter { includingCommonContext || !Self.commonContextKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "  ")
    }

    private static let commonContextKeys: Set<String> = [
        "frontmost_app",
        "frontmost_bundle",
        "frontmost_pid"
    ]

    private static let prettyHiddenMetadataKeys: Set<String> = [
        "active_app",
        "allow_screenshot_planning",
        "box_2d",
        "display_frame",
        "execute",
        "frontmost_app",
        "frontmost_bundle",
        "frontmost_pid",
        "label",
        "matched_source",
        "operation_token",
        "paused",
        "resolution_source",
        "resolved_label",
        "resolved_rect",
        "resolved_x",
        "resolved_y",
        "resolving",
        "source",
        "step_id",
        "target_app",
        "target_bundle",
        "target_id",
        "target_label",
        "target_mark",
        "trace_id",
        "target_pid",
        "value_preview",
        "x",
        "y"
    ]

    private func metadataValue(_ key: String, usedKeys: inout Set<String>) -> String? {
        guard let value = metadata[key], !value.isEmpty else { return nil }
        usedKeys.insert(key)
        return value
    }

    private func firstMetadataValue(_ keys: [String], usedKeys: inout Set<String>) -> String? {
        for key in keys {
            if let value = metadataValue(key, usedKeys: &usedKeys) {
                return value
            }
        }
        return nil
    }

    private func pointSummary(usedKeys: inout Set<String>) -> String? {
        let x = firstMetadataValue(["resolved_x", "x"], usedKeys: &usedKeys)
        let y = firstMetadataValue(["resolved_y", "y"], usedKeys: &usedKeys)
        guard let x, let y else { return nil }
        return "\(x),\(y)"
    }

    private func appendSummaryLine(
        title: String,
        pairs: [(String, String?)],
        to lines: inout [String]
    ) {
        let text = pairs.compactMap { key, value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: "  ")

        guard !text.isEmpty else { return }
        lines.append("  \(title): \(text)")
    }
}

@MainActor
final class PipelineLogStore: ObservableObject {
    static let shared = PipelineLogStore()

    @Published private(set) var events: [PipelineLogEvent] = []
    @Published private(set) var currentLogFilePath: String = ""

    private let maximumInMemoryEvents = 5000
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private init() {
        ensureLogDirectoryExists()
        currentLogFilePath = currentLogFileURL.path
        reloadFromDisk()
    }

    func record(
        category: String,
        name: String,
        status: String = "info",
        message: String? = nil,
        metadata: [String: String] = [:]
    ) {
        var enrichedMetadata = metadata
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            enrichedMetadata["frontmost_app"] = frontmostApplication.localizedName ?? "unknown"
            enrichedMetadata["frontmost_bundle"] = frontmostApplication.bundleIdentifier ?? "unknown"
            enrichedMetadata["frontmost_pid"] = String(frontmostApplication.processIdentifier)
        }

        let event = PipelineLogEvent(
            id: UUID().uuidString,
            timestamp: Self.iso8601Formatter.string(from: Date()),
            category: category,
            name: name,
            status: status,
            message: message,
            metadata: enrichedMetadata
        )

        events.append(event)
        if events.count > maximumInMemoryEvents {
            events.removeFirst(events.count - maximumInMemoryEvents)
        }
        appendToDisk(event)
    }

    func reloadFromDisk() {
        ensureLogDirectoryExists()
        currentLogFilePath = currentLogFileURL.path

        let decodedEvents = readEventsFromDisk()
        events = decodedEvents.count > maximumInMemoryEvents
            ? Array(decodedEvents.suffix(maximumInMemoryEvents))
            : decodedEvents
    }

    func revealLogFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([logsDirectoryURL])
    }

    func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func copyEventsAsJSONL(_ events: [PipelineLogEvent]) {
        copyToPasteboard(events.map(\.jsonLine).joined(separator: "\n"))
    }

    func clearLogs() {
        ensureLogDirectoryExists()
        let logFiles = (try? FileManager.default.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for fileURL in logFiles where fileURL.pathExtension == "jsonl" {
            try? FileManager.default.removeItem(at: fileURL)
        }

        events = []
        currentLogFilePath = currentLogFileURL.path
    }

    private func appendToDisk(_ event: PipelineLogEvent) {
        ensureLogDirectoryExists()
        currentLogFilePath = currentLogFileURL.path

        do {
            let data = try encoder.encode(event)
            var lineData = data
            lineData.append(Data("\n".utf8))
            if !FileManager.default.fileExists(atPath: currentLogFileURL.path) {
                FileManager.default.createFile(atPath: currentLogFileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: currentLogFileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
            try handle.close()
        } catch {
            print("[PipelineLog] failed to write log event: \(error.localizedDescription)")
        }
    }

    private func readEventsFromDisk() -> [PipelineLogEvent] {
        let decoder = JSONDecoder()
        let logFiles = (try? FileManager.default.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return logFiles
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { fileURL -> [PipelineLogEvent] in
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
                return text
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .compactMap { line -> PipelineLogEvent? in
                        guard let data = String(line).data(using: .utf8) else { return nil }
                        return try? decoder.decode(PipelineLogEvent.self, from: data)
                    }
            }
    }

    private func ensureLogDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: logsDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private var currentLogFileURL: URL {
        logsDirectoryURL.appendingPathComponent("tiptour-\(Self.dayFormatter.string(from: Date())).jsonl")
    }

    private var logsDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL
            .appendingPathComponent("TipTour", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private enum TipTourLogDisplayMode: String, CaseIterable, Identifiable {
    case pretty
    case raw

    var id: String { rawValue }
}

private struct TipTourLogsWindowView: View {
    @ObservedObject private var logStore = PipelineLogStore.shared
    @State private var filterText = ""
    @State private var displayMode: TipTourLogDisplayMode = .pretty

    private var visibleEvents: [PipelineLogEvent] {
        let trimmedFilter = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sourceEvents = logStore.events
        guard !trimmedFilter.isEmpty else { return Array(sourceEvents) }

        return sourceEvents.filter { event in
            event.jsonLine.lowercased().contains(trimmedFilter)
                || event.category.lowercased().contains(trimmedFilter)
                || event.name.lowercased().contains(trimmedFilter)
                || event.status.lowercased().contains(trimmedFilter)
                || (event.message?.lowercased().contains(trimmedFilter) == true)
                || event.metadata.values.contains { $0.lowercased().contains(trimmedFilter) }
        }
    }

    private var visibleJSONL: String {
        visibleEvents.map(\.jsonLine).joined(separator: "\n")
    }

    private var visiblePrettyText: String {
        visibleEvents.map(\.terminalBlock).joined(separator: "\n\n")
    }

    private var visibleText: String {
        switch displayMode {
        case .pretty:
            return visiblePrettyText
        case .raw:
            return visibleJSONL
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { visibleText },
            set: { _ in }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            TextEditor(text: textBinding)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Colors.textPrimary)
                .scrollContentBackground(.hidden)
                .background(terminalBackground)
                .textSelection(.enabled)
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(terminalBackground)
        .onAppear {
            logStore.reloadFromDisk()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("logs")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(DS.Colors.textTertiary)

            TextField("filter jsonl", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(terminalFieldBackground)

            Text("\(visibleEvents.count)/\(logStore.events.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Colors.textTertiary)

            modeButton(.pretty)
            modeButton(.raw)

            terminalAction("copy") {
                logStore.copyToPasteboard(visibleText)
            }

            terminalAction("reload") {
                logStore.reloadFromDisk()
            }

            terminalAction("clear") {
                logStore.clearLogs()
            }

            terminalAction("reveal") {
                logStore.revealLogFolder()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(terminalHeaderBackground)
        .help(logStore.currentLogFilePath)
    }

    private func modeButton(_ mode: TipTourLogDisplayMode) -> some View {
        Text(displayMode == mode ? "[\(mode.rawValue)]" : mode.rawValue)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(displayMode == mode ? DS.Colors.accent : DS.Colors.textTertiary)
            .contentShape(Rectangle())
            .onTapGesture {
                displayMode = mode
            }
    }

    private func terminalAction(_ title: String, action: @escaping () -> Void) -> some View {
        Text(title)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(DS.Colors.textSecondary)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private var terminalBackground: Color {
        Color(red: 0.04, green: 0.045, blue: 0.045)
    }

    private var terminalHeaderBackground: Color {
        Color(red: 0.055, green: 0.06, blue: 0.06)
    }

    private var terminalFieldBackground: Color {
        Color(red: 0.025, green: 0.028, blue: 0.028)
    }
}
