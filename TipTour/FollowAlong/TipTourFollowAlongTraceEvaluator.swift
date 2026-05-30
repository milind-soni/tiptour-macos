import Foundation

struct TipTourFollowAlongTraceEvaluator {
    struct Report {
        let text: String
    }

    func evaluate(jsonl: String) -> Report {
        let records = TipTourFollowAlongTraceStore.shared.decodeRecords(from: jsonl)
        guard !records.isEmpty else {
            return Report(text: "No trace records found.")
        }

        let total = records.count
        let okCount = records.filter(\.result.ok).count
        let failedCount = total - okCount
        let clickRecords = records.filter { isClickLike($0.preparedStep?.type ?? $0.draftStep.type) }
        let keyRecords = records.filter { isKeyLike($0.preparedStep?.type ?? $0.draftStep.type) }
        let textRecords = records.filter { isTextLike($0.preparedStep?.type ?? $0.draftStep.type) }
        let groundedClicks = clickRecords.filter { $0.chosenTarget != nil }
        let compatibleClicks = clickRecords.filter { record in
            guard let requested = requestedLabel(for: record),
                  let target = record.chosenTarget else {
                return false
            }
            return labelsAreCompatible(requested, target.label)
        }
        let stateMatchedClicks = clickRecords.filter { record in
            guard let target = record.chosenTarget else { return false }
            return record.stateActionState.targets.contains {
                $0.id == target.id || $0.mark == target.mark
            }
        }

        var lines: [String] = []
        lines.append("TipTour Follow-Along Trace Evaluation")
        lines.append("records=\(total)")
        lines.append("success_rate=\(percent(okCount, total)) (\(okCount)/\(total))")
        lines.append("failed=\(failedCount)")
        lines.append("click_grounding_rate=\(percent(groundedClicks.count, clickRecords.count)) (\(groundedClicks.count)/\(clickRecords.count))")
        lines.append("click_label_match_rate=\(percent(compatibleClicks.count, clickRecords.count)) (\(compatibleClicks.count)/\(clickRecords.count))")
        lines.append("click_state_match_rate=\(percent(stateMatchedClicks.count, clickRecords.count)) (\(stateMatchedClicks.count)/\(clickRecords.count))")
        lines.append("keyboard_success_rate=\(percent(keyRecords.filter(\.result.ok).count, keyRecords.count)) (\(keyRecords.filter(\.result.ok).count)/\(keyRecords.count))")
        lines.append("text_success_rate=\(percent(textRecords.filter(\.result.ok).count, textRecords.count)) (\(textRecords.filter(\.result.ok).count)/\(textRecords.count))")

        let findings = suspiciousRecords(records)
        if !findings.isEmpty {
            lines.append("")
            lines.append("Findings")
            for finding in findings.prefix(20) {
                lines.append("- \(finding)")
            }
        }

        return Report(text: lines.joined(separator: "\n"))
    }

    private func suspiciousRecords(_ records: [TipTourFollowAlongTraceStore.Record]) -> [String] {
        records.compactMap { record in
            let actionType = record.preparedStep?.type ?? record.draftStep.type
            if !record.result.ok {
                return "step \(record.stepIndex): \(actionType.rawValue) failed: \(record.result.message ?? record.result.reason ?? "unknown")"
            }

            guard isClickLike(actionType) else { return nil }
            guard let requested = requestedLabel(for: record) else {
                return "step \(record.stepIndex): click-like action has no requested label"
            }
            guard let target = record.chosenTarget else {
                return "step \(record.stepIndex): click '\(requested)' executed without a chosen target in trace"
            }
            if !labelsAreCompatible(requested, target.label) {
                return "step \(record.stepIndex): requested '\(requested)' but chose '\(target.label)'"
            }
            if !record.stateActionState.targets.contains(where: { $0.id == target.id || $0.mark == target.mark }) {
                return "step \(record.stepIndex): chose '\(target.label)' but it was not present in the matched pre-action state"
            }
            return nil
        }
    }

    private func requestedLabel(for record: TipTourFollowAlongTraceStore.Record) -> String? {
        let label = record.preparedStep?.label ?? record.draftStep.label
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isClickLike(_ type: WorkflowStep.StepType) -> Bool {
        switch type {
        case .click, .rightClick, .doubleClick:
            return true
        default:
            return false
        }
    }

    private func isKeyLike(_ type: WorkflowStep.StepType) -> Bool {
        switch type {
        case .keyboardShortcut, .pressKey:
            return true
        default:
            return false
        }
    }

    private func isTextLike(_ type: WorkflowStep.StepType) -> Bool {
        switch type {
        case .type, .setValue:
            return true
        default:
            return false
        }
    }

    private func percent(_ numerator: Int, _ denominator: Int) -> String {
        guard denominator > 0 else { return "n/a" }
        let value = Double(numerator) * 100 / Double(denominator)
        return String(format: "%.1f%%", value)
    }

    private func labelsAreCompatible(_ requestedLabel: String, _ candidateLabel: String) -> Bool {
        if normalizedText(requestedLabel) == normalizedText(candidateLabel) {
            return true
        }

        let requestedWords = normalizedWords(requestedLabel)
        let candidateWords = normalizedWords(candidateLabel)
        guard !requestedWords.isEmpty, !candidateWords.isEmpty else { return false }

        if requestedWords == candidateWords { return true }
        if requestedWords.count == 1,
           candidateWords.count == 1,
           let requested = requestedWords.first,
           let candidate = candidateWords.first {
            return requested == candidate || editDistance(requested, candidate) <= 1
        }

        return requestedWords.isSubset(of: candidateWords)
            || candidateWords.isSubset(of: requestedWords)
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
        return Set(
            text
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { word -> String in
                    let alias = aliases[word] ?? word
                    if alias.count > 4, alias.hasSuffix("s") {
                        return String(alias.dropLast())
                    }
                    return alias
                }
                .filter { !$0.isEmpty && !["the", "a", "an", "click", "open", "select"].contains($0) }
        )
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
}
