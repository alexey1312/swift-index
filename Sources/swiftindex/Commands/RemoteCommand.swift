import ArgumentParser

struct RemoteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remote",
        abstract: "Configure and inspect remote storage",
        subcommands: [
            RemoteConfigCommand.self,
            RemoteStatusCommand.self,
        ]
    )
}
