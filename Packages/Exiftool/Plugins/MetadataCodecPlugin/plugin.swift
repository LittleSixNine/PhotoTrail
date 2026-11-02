import Foundation
import PackagePlugin

@main struct MetadataCodecPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let tools = context.package.directoryURL.appendingPathComponent("Tools")
        let source = tools.appendingPathComponent("MetadataBrotli.c")
        let script = tools.appendingPathComponent("build-metadata-codec.sh")
        let output = context.pluginWorkDirectoryURL.appendingPathComponent("MetadataBrotli.bin")
        return [.buildCommand(displayName: "Build metadata Brotli codec",
            executable: URL(fileURLWithPath: "/bin/sh"), arguments: [script.path, source.path, output.path],
            inputFiles: [source, script], outputFiles: [output])]
    }
}
