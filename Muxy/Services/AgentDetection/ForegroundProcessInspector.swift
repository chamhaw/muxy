import Darwin
import Foundation

enum ForegroundProcessInspector {
    struct ProcessIdentity: Equatable {
        let processID: UInt64
        let parentProcessID: UInt64
        let processGroupID: UInt64
    }

    private static let scriptInterpreters: Set<String> = [
        "node",
        "bun",
        "deno",
        "python",
        "python3",
        "ruby",
        "perl",
        "sh",
        "bash",
        "zsh",
    ]

    static func executableNameCandidates(pid: UInt64) -> [String] {
        executableNameCandidates(
            foregroundProcessID: pid,
            processIdentity: processIdentity(pid:),
            invocation: ProcessArgumentsInspector.invocation(pid:)
        )
    }

    static func executableNameCandidates(
        foregroundProcessID: UInt64,
        processIdentity: (UInt64) -> ProcessIdentity?,
        invocation: (UInt64) -> ProcessInvocation?
    ) -> [String] {
        guard let foregroundProcess = processIdentity(foregroundProcessID) else { return [] }

        var candidates: [String] = []
        var process: ProcessIdentity? = foregroundProcess
        var visitedProcessIDs: Set<UInt64> = []
        while let current = process,
              current.processGroupID == foregroundProcess.processGroupID,
              visitedProcessIDs.insert(current.processID).inserted
        {
            if let currentInvocation = invocation(current.processID) {
                candidates.append(contentsOf: executableNameCandidates(for: currentInvocation))
            }
            process = processIdentity(current.parentProcessID)
        }
        return candidates
    }

    private static func executableNameCandidates(for invocation: ProcessInvocation) -> [String] {
        var candidates: [String] = []
        let executableName = lastPathComponent(of: invocation.executablePath)
        if let executableName {
            candidates.append(executableName)
        }

        let argumentNames = invocation.arguments.compactMap(lastPathComponent)
        if let firstArgument = argumentNames.first {
            candidates.append(firstArgument)
        }

        if isScriptInterpreter(executableName: executableName, firstArgument: argumentNames.first),
           argumentNames.count > 1
        {
            candidates.append(argumentNames[1])
        }
        return candidates
    }

    private static func processIdentity(pid: UInt64) -> ProcessIdentity? {
        guard pid > 0, pid <= UInt64(Int32.max) else { return nil }

        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return ProcessIdentity(
            processID: UInt64(info.pbi_pid),
            parentProcessID: UInt64(info.pbi_ppid),
            processGroupID: UInt64(info.pbi_pgid)
        )
    }

    private static func isScriptInterpreter(executableName: String?, firstArgument: String?) -> Bool {
        if let executableName, scriptInterpreters.contains(executableName) {
            return true
        }
        if let firstArgument, scriptInterpreters.contains(firstArgument) {
            return true
        }
        return false
    }

    private static func lastPathComponent(of path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let component = (trimmed as NSString).lastPathComponent
        return component.isEmpty ? nil : component
    }
}
