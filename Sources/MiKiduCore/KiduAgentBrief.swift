import Foundation

public enum KiduAgentProvider: String, CaseIterable, Identifiable, Sendable {
    case openClaw, codex, claude, localAdapter

    public var id: Self { self }

    public var title: String {
        switch self {
        case .openClaw: "OpenClaw"
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .localAdapter: "Otro agente"
        }
    }

    public var officialURL: URL? {
        switch self {
        case .openClaw: URL(string: "https://docs.openclaw.ai/tui")!
        case .codex: URL(string: "https://chatgpt.com/codex/")!
        case .claude: URL(string: "https://claude.ai/")!
        case .localAdapter: nil
        }
    }
}

/// El encargo se construye únicamente a partir de los campos que completa la persona.
public struct KiduAgentBrief: Equatable, Sendable {
    public static let maximumFieldLength = 4_000

    public var goal = ""
    public var context = ""
    public var limits = ""
    public var deliverable = ""

    public init() {}

    public func prepare() throws -> String {
        let fields = [goal, context, limits, deliverable]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !fields[0].isEmpty else { throw PreparationError.missingGoal }
        guard fields.allSatisfy({ $0.count <= Self.maximumFieldLength }) else {
            throw PreparationError.tooLong
        }
        let sections = zip(["Objetivo", "Contexto", "Límites", "Resultado esperado"], fields)
            .filter { !$0.1.isEmpty }.map { "\($0.0)\n\($0.1)" }
        return sections.joined(separator: "\n\n")
    }

    public enum PreparationError: Error, Equatable, LocalizedError {
        case missingGoal, tooLong

        public var errorDescription: String? {
            switch self {
            case .missingGoal: "Escribe un objetivo."
            case .tooLong: "Limita cada campo a 4.000 caracteres."
            }
        }
    }
}
