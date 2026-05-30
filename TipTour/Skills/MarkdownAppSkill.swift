//
//  MarkdownAppSkill.swift
//  TipTour
//
//  Loads portable markdown skills and exposes only the tiny runtime hints
//  TipTour needs to ground and execute one action cleanly.
//

import AppKit
import Foundation

struct MarkdownAppSkillRuntimeHints: Decodable {
    let appMatchers: AppMatchers?
    let commandAliases: [CommandAlias]
    let inputPolicies: [InputPolicy]
    let targetPolicies: TargetPolicies?
    let followAlongRewrites: [FollowAlongRewrite]?
    let plannerInstructions: [String]

    struct AppMatchers: Decodable {
        let bundleIdentifiers: [String]
        let names: [String]
    }

    struct CommandAlias: Decodable {
        let phrases: [String]
        let type: WorkflowStep.StepType
        let label: String
    }

    struct InputPolicy: Decodable {
        let kind: String
        let delivery: String
        let maxLength: Int?
        let characters: String?
    }

    struct TargetPolicies: Decodable {
        let menuSelection: MenuSelection?

        struct MenuSelection: Decodable {
            let preferLeftMenuRegionMaxX: Double?
        }
    }

    struct FollowAlongRewrite: Decodable {
        let phrases: [String]
        let actionTypes: [WorkflowStep.StepType]?
        let type: WorkflowStep.StepType
        let label: String?
        let visibleLabelsInOrder: [String]?
        let value: String?
        let targetContext: WorkflowStep.TargetContext?
    }
}

struct MarkdownAppSkill {
    let name: String
    let description: String
    let source: String
    let path: String
    let markdown: String
    let runtimeHints: MarkdownAppSkillRuntimeHints

    func matches(applicationName: String?, bundleIdentifier: String?) -> Bool {
        let normalizedApplicationName = Self.normalizedMatcherText(applicationName ?? "")
        let normalizedBundleIdentifier = (bundleIdentifier ?? "").lowercased()

        if runtimeHints.appMatchers?.bundleIdentifiers.contains(where: {
            normalizedBundleIdentifier == $0.lowercased()
        }) == true {
            return true
        }

        return runtimeHints.appMatchers?.names.contains(where: {
            normalizedApplicationName.contains(Self.normalizedMatcherText($0))
        }) == true
    }

    func commandAlias(for commandText: String) -> MarkdownAppSkillRuntimeHints.CommandAlias? {
        let normalizedCommandText = Self.normalizedCommandText(commandText)
        return runtimeHints.commandAliases.first { commandAlias in
            commandAlias.phrases.contains {
                normalizedCommandText == Self.normalizedCommandText($0)
                    || normalizedCommandText.contains(Self.normalizedCommandText($0))
            }
        }
    }

    func shouldTypeUsingPhysicalKeys(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return false }

        return runtimeHints.inputPolicies.contains { inputPolicy in
            guard inputPolicy.kind == "numericModalText",
                  inputPolicy.delivery == "physicalKeys" else {
                return false
            }

            if let maxLength = inputPolicy.maxLength, trimmedText.count > maxLength {
                return false
            }

            if let allowedCharacters = inputPolicy.characters {
                let allowedCharacterSet = CharacterSet(charactersIn: allowedCharacters)
                guard trimmedText.rangeOfCharacter(from: allowedCharacterSet.inverted) == nil else {
                    return false
                }
            }

            return trimmedText.rangeOfCharacter(from: .decimalDigits) != nil
        }
    }

    func followAlongRewrite(
        for step: WorkflowStep,
        sourceText: String,
        visibleTargets: [LocalPerceptionTargetCache.SnapshotTarget] = []
    ) -> MarkdownAppSkillRuntimeHints.FollowAlongRewrite? {
        let normalizedCommandText = Self.normalizedCommandText(
            "\(sourceText) \(step.hint) \(step.label ?? "")"
        )
        guard let rewrite = runtimeHints.followAlongRewrites?.first(where: { rewrite in
            if let actionTypes = rewrite.actionTypes,
               !actionTypes.contains(step.type) {
                return false
            }
            return rewrite.phrases.contains {
                normalizedCommandText.contains(Self.normalizedCommandText($0))
            }
        }) else {
            return nil
        }

        guard let visibleLabelsInOrder = rewrite.visibleLabelsInOrder,
              !visibleLabelsInOrder.isEmpty,
              let visibleLabel = Self.firstVisibleLabel(
                from: visibleLabelsInOrder,
                visibleTargets: visibleTargets
              ) else {
            return rewrite
        }

        return MarkdownAppSkillRuntimeHints.FollowAlongRewrite(
            phrases: rewrite.phrases,
            actionTypes: rewrite.actionTypes,
            type: rewrite.type,
            label: visibleLabel,
            visibleLabelsInOrder: rewrite.visibleLabelsInOrder,
            value: rewrite.value,
            targetContext: rewrite.targetContext
        )
    }

    var menuSelectionPreferredLeftRegionMaxX: Double? {
        runtimeHints.targetPolicies?.menuSelection?.preferLeftMenuRegionMaxX
    }

    var appNames: [String] {
        runtimeHints.appMatchers?.names ?? []
    }

    var bundleIdentifiers: [String] {
        runtimeHints.appMatchers?.bundleIdentifiers ?? []
    }

    func info(isActive: Bool) -> MarkdownAppSkillInfo {
        MarkdownAppSkillInfo(
            name: name,
            description: description,
            source: source,
            path: path,
            appNames: appNames,
            bundleIdentifiers: bundleIdentifiers,
            plannerInstructionCount: runtimeHints.plannerInstructions.count,
            plannerInstructions: runtimeHints.plannerInstructions,
            isActive: isActive
        )
    }

    static func normalizedCommandText(_ text: String) -> String {
        text
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func firstVisibleLabel(
        from preferredLabels: [String],
        visibleTargets: [LocalPerceptionTargetCache.SnapshotTarget]
    ) -> String? {
        for preferredLabel in preferredLabels {
            let normalizedPreferredLabel = normalizedCommandText(preferredLabel)
            guard !normalizedPreferredLabel.isEmpty else { continue }
            if let target = visibleTargets.first(where: {
                normalizedCommandText($0.label) == normalizedPreferredLabel
            }) {
                return target.label
            }
        }
        return nil
    }

    private static func normalizedMatcherText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct MarkdownAppSkillInfo: Encodable {
    let name: String
    let description: String
    let source: String
    let path: String
    let appNames: [String]
    let bundleIdentifiers: [String]
    let plannerInstructionCount: Int
    let plannerInstructions: [String]
    let isActive: Bool
}

@MainActor
final class MarkdownAppSkillRegistry {
    static let shared = MarkdownAppSkillRegistry()

    private let skills: [MarkdownAppSkill]

    init(fileManager: FileManager = .default) {
        skills = Self.loadSkills(fileManager: fileManager)
        if !skills.isEmpty {
            print("[Skills] loaded markdown app skills: \(skills.map(\.name).joined(separator: ", "))")
        }
    }

    var allSkills: [MarkdownAppSkill] {
        skills
    }

    func skill(for application: NSRunningApplication?) -> MarkdownAppSkill? {
        skill(
            applicationName: application?.localizedName,
            bundleIdentifier: application?.bundleIdentifier
        )
    }

    func skill(applicationName: String?, bundleIdentifier: String? = nil) -> MarkdownAppSkill? {
        skills.first {
            $0.matches(
                applicationName: applicationName,
                bundleIdentifier: bundleIdentifier
            )
        }
    }

    func plannerInstructions(for application: NSRunningApplication?) -> String? {
        guard let skill = skill(for: application),
              !skill.runtimeHints.plannerInstructions.isEmpty else {
            return nil
        }

        return """
        Active app skill: \(skill.name)
        \(skill.runtimeHints.plannerInstructions.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    func skillInfos(activeApplication: NSRunningApplication?) -> [MarkdownAppSkillInfo] {
        let activeSkillName = skill(for: activeApplication)?.name
        return skills.map { skill in
            skill.info(isActive: skill.name == activeSkillName)
        }
    }

    func activeSkillInfo(for application: NSRunningApplication?) -> MarkdownAppSkillInfo? {
        skill(for: application)?.info(isActive: true)
    }

    private static func loadSkills(fileManager: FileManager) -> [MarkdownAppSkill] {
        var loadedSkills: [MarkdownAppSkill] = []
        var seenSkillNames = Set<String>()

        for skillRoot in skillRoots(fileManager: fileManager) {
            for skillURL in skillURLs(in: skillRoot.url, fileManager: fileManager) {
                guard let skill = loadSkill(from: skillURL, source: skillRoot.source) else { continue }
                let normalizedSkillName = skill.name.lowercased()
                guard seenSkillNames.insert(normalizedSkillName).inserted else { continue }
                loadedSkills.append(skill)
            }
        }

        return loadedSkills
    }

    private static func skillRoots(fileManager: FileManager) -> [SkillRoot] {
        var candidateSkillRoots: [SkillRoot] = []

        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        candidateSkillRoots.append(
            SkillRoot(
                url: homeDirectoryURL.appendingPathComponent(".tiptour/skills", isDirectory: true),
                source: "user"
            )
        )

        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        candidateSkillRoots.append(contentsOf: projectSkillRoots(under: currentDirectoryURL))

        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRootURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidateSkillRoots.append(contentsOf: projectSkillRoots(under: repositoryRootURL))

        if let resourceURL = Bundle.main.resourceURL {
            candidateSkillRoots.append(
                SkillRoot(
                    url: resourceURL.appendingPathComponent("Skills", isDirectory: true),
                    source: "bundled"
                )
            )
            candidateSkillRoots.append(
                SkillRoot(
                    url: resourceURL.appendingPathComponent("TipTour/Skills", isDirectory: true),
                    source: "bundled"
                )
            )
        }

        candidateSkillRoots.append(
            SkillRoot(
                url: repositoryRootURL.appendingPathComponent("TipTour/Skills", isDirectory: true),
                source: "bundled-source"
            )
        )

        var seenPaths = Set<String>()
        return candidateSkillRoots.filter { skillRoot in
            guard fileManager.fileExists(atPath: skillRoot.url.path) else { return false }
            return seenPaths.insert(skillRoot.url.standardizedFileURL.path).inserted
        }
    }

    private static func projectSkillRoots(under rootURL: URL) -> [SkillRoot] {
        [
            SkillRoot(url: rootURL.appendingPathComponent(".claude/skills", isDirectory: true), source: "project"),
            SkillRoot(url: rootURL.appendingPathComponent(".agents/skills", isDirectory: true), source: "project"),
            SkillRoot(url: rootURL.appendingPathComponent(".openhands/skills", isDirectory: true), source: "project"),
            SkillRoot(url: rootURL.appendingPathComponent(".openhands/microagents", isDirectory: true), source: "project")
        ]
    }

    private static func skillURLs(in rootURL: URL, fileManager: FileManager) -> [URL] {
        guard let directoryEnumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directoryEnumerator
            .compactMap { $0 as? URL }
            .filter { skillURL in
                guard skillURL.pathExtension.lowercased() == "md" else { return false }
                return skillURL.lastPathComponent == "SKILL.md"
                    || skillURL.lastPathComponent.lowercased() != "readme.md"
            }
    }

    private static func loadSkill(from skillURL: URL, source: String) -> MarkdownAppSkill? {
        guard let markdown = try? String(contentsOf: skillURL, encoding: .utf8),
              let runtimeHintsJSON = fencedCodeBlock(named: "tiptour-runtime-hints", in: markdown),
              let runtimeHintsData = runtimeHintsJSON.data(using: .utf8),
              let runtimeHints = try? JSONDecoder().decode(MarkdownAppSkillRuntimeHints.self, from: runtimeHintsData) else {
            return nil
        }

        let metadata = frontMatterMetadata(in: markdown)
        return MarkdownAppSkill(
            name: metadata["name"] ?? skillURL.deletingLastPathComponent().lastPathComponent,
            description: metadata["description"] ?? "",
            source: source,
            path: skillURL.path,
            markdown: markdown,
            runtimeHints: runtimeHints
        )
    }

    private static func frontMatterMetadata(in markdown: String) -> [String: String] {
        guard markdown.hasPrefix("---\n"),
              let endRange = markdown.range(of: "\n---", range: markdown.index(markdown.startIndex, offsetBy: 4)..<markdown.endIndex) else {
            return [:]
        }

        let frontMatter = markdown[markdown.index(markdown.startIndex, offsetBy: 4)..<endRange.lowerBound]
        var metadata: [String: String] = [:]
        for line in frontMatter.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }
            metadata[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return metadata
    }

    private static func fencedCodeBlock(named blockName: String, in markdown: String) -> String? {
        let fenceStart = "```\(blockName)"
        guard let startRange = markdown.range(of: fenceStart) else { return nil }
        let contentStartIndex = startRange.upperBound
        guard let newlineRange = markdown.range(of: "\n", range: contentStartIndex..<markdown.endIndex) else { return nil }
        guard let endRange = markdown.range(of: "\n```", range: newlineRange.upperBound..<markdown.endIndex) else { return nil }
        return String(markdown[newlineRange.upperBound..<endRange.lowerBound])
    }

    private struct SkillRoot {
        let url: URL
        let source: String
    }
}
