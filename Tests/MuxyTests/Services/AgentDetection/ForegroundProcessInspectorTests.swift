import Darwin
import Foundation
import Testing

@testable import Muxy

@Suite("ForegroundProcessInspector")
struct ForegroundProcessInspectorTests {
    @Test("resolves executable name candidates for the current process")
    func resolvesCurrentProcess() {
        let pid = UInt64(getpid())
        let candidates = ForegroundProcessInspector.executableNameCandidates(pid: pid)
        #expect(!candidates.isEmpty)
        #expect(candidates.allSatisfy { !$0.contains("/") })
    }

    @Test("returns no candidates for an invalid pid")
    func returnsEmptyForInvalidPID() {
        #expect(ForegroundProcessInspector.executableNameCandidates(pid: 0).isEmpty)
    }

    @Test("detects an interpreter-launched agent via the script argument")
    func detectsInterpreterLaunchedAgent() {
        let executables = [AIAgentExecutable(providerID: "codex", executableNames: ["codex"])]
        let nodeWrapperCandidates = ["node", "node", "codex"]
        #expect(
            AIAgentDetector.providerID(forCandidateNames: nodeWrapperCandidates, executables: executables) == "codex"
        )
    }

    @Test("detects Kiro through same-group interactive ancestors")
    func detectsKiroThroughInteractiveAncestors() {
        let invocations: [UInt64: ProcessInvocation] = [
            30: ProcessInvocation(executablePath: "/opt/homebrew/bin/bun", arguments: ["bun", "tui.js"]),
            20: ProcessInvocation(executablePath: "/opt/homebrew/bin/kiro-cli-chat", arguments: ["kiro-cli-chat"]),
            10: ProcessInvocation(executablePath: "/opt/homebrew/bin/kiro-cli", arguments: ["kiro-cli"]),
        ]
        let processes = [
            ForegroundProcessInspector.ProcessIdentity(processID: 30, parentProcessID: 20, processGroupID: 10),
            ForegroundProcessInspector.ProcessIdentity(processID: 20, parentProcessID: 10, processGroupID: 10),
            ForegroundProcessInspector.ProcessIdentity(processID: 10, parentProcessID: 1, processGroupID: 10),
        ]

        let candidates = ForegroundProcessInspector.executableNameCandidates(
            foregroundProcessID: 30,
            processIdentity: { processID in processes.first { $0.processID == processID } },
            invocation: { processID in invocations[processID] }
        )

        #expect(candidates == ["bun", "bun", "tui.js", "kiro-cli-chat", "kiro-cli-chat", "kiro-cli", "kiro-cli"])
        #expect(
            AIAgentDetector.providerID(
                forCandidateNames: candidates,
                executables: [AIAgentExecutable(providerID: "kiro", executableNames: ["kiro-cli"])]
            ) == "kiro"
        )
    }

    @Test("excludes ancestors outside the foreground process group")
    func excludesAncestorsOutsideForegroundProcessGroup() {
        let invocations: [UInt64: ProcessInvocation] = [
            30: ProcessInvocation(executablePath: "/opt/homebrew/bin/bun", arguments: ["bun", "tui.js"]),
            20: ProcessInvocation(executablePath: "/opt/homebrew/bin/kiro-cli-chat", arguments: ["kiro-cli-chat"]),
            10: ProcessInvocation(executablePath: "/opt/homebrew/bin/kiro-cli", arguments: ["kiro-cli"]),
            1: ProcessInvocation(executablePath: "/opt/homebrew/bin/codex", arguments: ["codex"]),
        ]
        let processes = [
            ForegroundProcessInspector.ProcessIdentity(processID: 30, parentProcessID: 20, processGroupID: 10),
            ForegroundProcessInspector.ProcessIdentity(processID: 20, parentProcessID: 10, processGroupID: 10),
            ForegroundProcessInspector.ProcessIdentity(processID: 10, parentProcessID: 1, processGroupID: 10),
            ForegroundProcessInspector.ProcessIdentity(processID: 1, parentProcessID: 0, processGroupID: 1),
        ]

        let candidates = ForegroundProcessInspector.executableNameCandidates(
            foregroundProcessID: 30,
            processIdentity: { processID in processes.first { $0.processID == processID } },
            invocation: { processID in invocations[processID] }
        )

        #expect(!candidates.contains("codex"))
        #expect(
            AIAgentDetector.providerID(
                forCandidateNames: candidates,
                executables: [AIAgentExecutable(providerID: "codex", executableNames: ["codex"])]
            ) == nil
        )
    }

    @Test("preserves single-process Codex and Claude detection")
    func preservesSingleProcessAgentDetection() {
        let processes = [
            ForegroundProcessInspector.ProcessIdentity(processID: 10, parentProcessID: 1, processGroupID: 10),
        ]
        let executables = [
            AIAgentExecutable(providerID: "codex", executableNames: ["codex"]),
            AIAgentExecutable(providerID: "claude", executableNames: ["claude"]),
        ]

        for (path, providerID) in [("/opt/homebrew/bin/codex", "codex"), ("/opt/homebrew/bin/claude", "claude")] {
            let candidates = ForegroundProcessInspector.executableNameCandidates(
                foregroundProcessID: 10,
                processIdentity: { processID in processes.first { $0.processID == processID } },
                invocation: { _ in ProcessInvocation(executablePath: path, arguments: [path]) }
            )
            #expect(AIAgentDetector.providerID(forCandidateNames: candidates, executables: executables) == providerID)
        }
    }
}
