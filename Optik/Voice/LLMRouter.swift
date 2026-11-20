import Foundation
import OptikCore

/// Picks how Optik reaches Claude, per request: the API when there is a key (the
/// fastest), otherwise Claude Code with the user's subscription, if its script is
/// installed. Without either, the conversation repeats what it heard.
final class LLMRouter: LLMClient {
    private let api: any LLMClient
    private let claudeCode: any LLMClient

    init(api: any LLMClient = ClaudeClient(), claudeCode: any LLMClient = ClaudeCodeClient()) {
        self.api = api
        self.claudeCode = claudeCode
    }

    private var current: any LLMClient {
        Self.usesClaudeCode ? claudeCode : api
    }

    static var usesClaudeCode: Bool {
        !KeychainStore.has(.anthropic) && ClaudeCodeClient.isInstalled
    }

    /// Optik can use the computer: only through Claude Code for now, which reaches
    /// the tools over `ComputerServer`.
    static var canUseComputer: Bool {
        usesClaudeCode && ComputerServer.shared.configPath != nil
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMEvent, Error> {
        current.stream(request)
    }

    func warmUp() async {
        await current.warmUp()
    }
}
