import Foundation
import Testing
@testable import BunnyCore

struct ShellEnvironmentTests {
    @Test func loginPATHContainsSystemDirectories() {
        let components = ShellEnvironment.loginPATH().split(separator: ":").map(String.init)
        #expect(components.contains("/usr/bin"))
        #expect(components.contains("/bin"))
        #expect(!ShellEnvironment.loginPATH().contains("__BUNNY_PATH__"))
    }

    @Test func locateFindsCommandsOnLoginPATH() throws {
        let sh = try #require(ShellEnvironment.locate("sh"))
        #expect(sh.hasPrefix("/"))
        #expect(FileManager.default.isExecutableFile(atPath: sh))
        #expect(ShellEnvironment.locate("bunny-no-such-command-xyz") == nil)
        #expect(ShellEnvironment.locate("") == nil)
    }

    @Test func locateCachesAndRefreshes() {
        let first = ShellEnvironment.locate("ls")
        let cached = ShellEnvironment.locate("ls")
        let refreshed = ShellEnvironment.locate("ls", refresh: true)
        #expect(first != nil)
        #expect(cached == first)
        #expect(refreshed == first)
    }

    @Test func locateAcceptsAbsoluteExecutablePaths() {
        #expect(ShellEnvironment.locate("/bin/sh") == "/bin/sh")
        #expect(ShellEnvironment.locate("/nonexistent/claude") == nil)
    }

    @Test func safeToCallConcurrentlyOffMain() async {
        let results = await withTaskGroup(of: String?.self) { group in
            for index in 0..<8 {
                group.addTask {
                    index.isMultiple(of: 2) ? ShellEnvironment.locate("sh") : ShellEnvironment.environment()["PATH"]
                }
            }
            var collected: [String?] = []
            for await result in group { collected.append(result) }
            return collected
        }
        #expect(results.count == 8)
        #expect(results.allSatisfy { $0 != nil })
    }

    @Test func environmentOverridesPATHAndTerminal() {
        let environment = ShellEnvironment.environment()
        #expect(environment["PATH"] == ShellEnvironment.loginPATH())
        #expect(environment["TERM"] == "dumb")
        #expect(environment["NO_COLOR"] == "1")
        #expect(environment["HOME"] == ProcessInfo.processInfo.environment["HOME"])
    }
}
