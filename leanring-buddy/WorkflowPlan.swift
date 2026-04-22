//
//  WorkflowPlan.swift
//  TipTour
//
//  Schema for AI-generated interactive tutorials. The LLM emits a
//  structured plan (JSON) describing a multi-step workflow — we
//  resolve and execute the steps one at a time.
//
//  This is the foundation for what will eventually become a full
//  step-runner with click detection + state verification. Right now
//  we only act on the first step (fly the cursor there) and display
//  the rest as a preview — but the shape of the plan is already
//  built to grow into that.
//

import Foundation
import CoreGraphics

/// A single action in a workflow. Most steps today are `click` with a
/// label; the enum is extensible so we can add `type`, `scroll`,
/// `wait_for_state`, `keyboard_shortcut`, etc. without breaking the
/// schema.
struct WorkflowStep: Codable, Identifiable, Hashable {
    /// Stable id for SwiftUI lists and referring to this step from others.
    /// Generated from the step index at parse time if the LLM doesn't
    /// provide one.
    let id: String

    /// What kind of action this step represents.
    /// Today we execute only .click. Others are reserved for future use.
    let type: StepType

    /// Human-readable label for the element, e.g. "File", "New",
    /// "General template". Passed to ElementResolver for pixel lookup.
    let label: String?

    /// Short sentence describing what the user should do at this step.
    /// Used for the on-screen step list UI (e.g. "Click the File menu").
    let hint: String

    /// Optional hint coordinate from the LLM. Used by ElementResolver
    /// for YOLO proximity snapping when AX/OCR labels don't resolve.
    let hintX: Int?
    let hintY: Int?

    /// Which screen the action happens on (for multi-monitor). nil =
    /// use the cursor's current screen.
    let screenNumber: Int?

    enum StepType: String, Codable, Hashable {
        case click            // point at and click an element
        case keyboardShortcut // press a specific key combo (e.g. "Cmd+N")
        case type             // type text into a focused field
        case scroll           // scroll in a specific direction
        case waitForState     // pause until a condition is visually satisfied
        case observe          // nothing to do — just highlight for the user
    }

    /// Convenience — the LLM's coordinate hint as a CGPoint if both
    /// components are present.
    var hintCoordinate: CGPoint? {
        guard let hintX, let hintY else { return nil }
        return CGPoint(x: hintX, y: hintY)
    }
}

/// A complete workflow — one user question's answer expressed as an
/// ordered sequence of steps.
struct WorkflowPlan: Codable, Hashable {
    /// High-level description of what the workflow achieves.
    /// Shown as the title of the step-list UI.
    let goal: String

    /// The app this workflow targets. Used for app-switching and
    /// deciding whether the plan is still applicable when the user
    /// changes focus.
    let app: String?

    /// Ordered list of steps. The app executes them one at a time.
    let steps: [WorkflowStep]
}

// MARK: - Parsing

extension WorkflowPlan {

    /// Parse a workflow plan from a JSON string. Accepts either a
    /// fenced `json ...` code block (typical LLM response) or a raw
    /// JSON object. Returns nil if the input isn't a valid plan.
    ///
    /// This is deliberately tolerant — LLMs sometimes emit extra
    /// whitespace, leading prose, or trailing explanations. We extract
    /// the first `{ ... }` JSON object we find and try to parse that.
    static func parse(from text: String) -> WorkflowPlan? {
        guard let jsonSubstring = extractFirstJSONObject(from: text) else { return nil }
        guard let data = jsonSubstring.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()
        if let plan = try? decoder.decode(WorkflowPlan.self, from: data) {
            return plan
        }

        // Fallback: the LLM might have given us a raw array of steps
        // wrapped in a schema-less object. Try to handle common variants.
        if let flexibleSteps = try? decoder.decode(FlexiblePlanPayload.self, from: data) {
            return flexibleSteps.toPlan()
        }

        return nil
    }

    /// Scan the string for the first balanced `{ ... }` JSON object.
    /// Handles nested braces correctly.
    private static func extractFirstJSONObject(from text: String) -> String? {
        var depth = 0
        var startIndex: String.Index?
        for i in text.indices {
            let ch = text[i]
            if ch == "{" {
                if depth == 0 { startIndex = i }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let start = startIndex {
                    return String(text[start...i])
                }
            }
        }
        return nil
    }
}

// MARK: - Flexible Payload (tolerates minor schema drift)

/// Used as a fallback when the LLM's JSON doesn't exactly match our
/// strict schema. Accepts common variations in key names and makes
/// a best-effort conversion to a WorkflowPlan.
private struct FlexiblePlanPayload: Codable {
    let goal: String?
    let title: String?
    let app: String?
    let steps: [FlexibleStep]?
    let plan: [FlexibleStep]?

    struct FlexibleStep: Codable {
        let id: String?
        let type: String?
        let action: String?
        let label: String?
        let target: String?
        let element: String?
        let hint: String?
        let description: String?
        let x: Int?
        let y: Int?
        let screenNumber: Int?
        let screen: Int?
    }

    func toPlan() -> WorkflowPlan? {
        let rawSteps = steps ?? plan ?? []
        guard !rawSteps.isEmpty else { return nil }

        let normalizedSteps: [WorkflowStep] = rawSteps.enumerated().map { index, s in
            let typeString = (s.type ?? s.action ?? "click").lowercased()
            let stepType = WorkflowStep.StepType(rawValue: typeString) ?? .click
            return WorkflowStep(
                id: s.id ?? "step_\(index + 1)",
                type: stepType,
                label: s.label ?? s.target ?? s.element,
                hint: s.hint ?? s.description ?? "",
                hintX: s.x,
                hintY: s.y,
                screenNumber: s.screenNumber ?? s.screen
            )
        }

        return WorkflowPlan(
            goal: goal ?? title ?? "Workflow",
            app: app,
            steps: normalizedSteps
        )
    }
}
