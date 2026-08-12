import Foundation

struct KiroProvider: AIAgentLaunchProvider {
    let id = "kiro"
    let displayName = "Kiro CLI"
    let iconName = "kiro"
    let agentExecutableNames = ["kiro-cli"]

    var agentLaunchConfiguration: AIAgentLaunchConfiguration {
        AIAgentLaunchConfiguration(
            executable: "kiro-cli",
            interactiveArguments: ["chat"],
            headlessArguments: ["chat", "--no-interactive", "--trust-tools="]
        )
    }

    private let homeDirectory: String
    private let pathEnvironment: @Sendable () -> String

    init(
        homeDirectory: String = NSHomeDirectory(),
        pathEnvironment: @escaping @Sendable () -> String = { LoginShellPath.current }
    ) {
        self.homeDirectory = homeDirectory
        self.pathEnvironment = pathEnvironment
    }

    init(
        homeDirectory: String = NSHomeDirectory(),
        pathEnvironment: String
    ) {
        self.init(homeDirectory: homeDirectory, pathEnvironment: { pathEnvironment })
    }

    func agentCLIExecutablePath() -> String? {
        ProviderExecutableLocator.executablePath(
            names: [agentLaunchConfiguration.executable],
            homeDirectory: homeDirectory,
            pathEnvironment: pathEnvironment(),
            includeSystemWide: homeDirectory == NSHomeDirectory()
        )
    }
}
