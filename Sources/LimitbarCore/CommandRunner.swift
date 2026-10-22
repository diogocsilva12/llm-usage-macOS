import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A bounded, isolated command invocation. Output and raw diagnostics never reach logs.
public enum CommandRunner {
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval,
                           environment: [String: String], guardBrowser: Bool = false) async throws -> Data {
        let task = Task.detached(priority: .utility) {
            try runSync(executable: executable, arguments: arguments, timeout: timeout,
                        environment: environment, guardBrowser: guardBrowser)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    private static func runSync(executable: URL, arguments: [String], timeout: TimeInterval,
                                environment: [String: String], guardBrowser: Bool) throws -> Data {
        try Task.checkCancellation()
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("limitbar-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: directory) }
        let output = directory.appendingPathComponent("stdout")
        var environment = environment
        if guardBrowser {
            for name in ["open", "xdg-open", "no-browser"] {
                let path = directory.appendingPathComponent(name)
                try Data("#!/bin/sh\nexit 1\n".utf8).write(to: path)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
            }
            environment["BROWSER"] = directory.appendingPathComponent("no-browser").path
            environment["PATH"] = directory.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        }

        return try spawn(executable: executable, arguments: arguments, environment: environment,
                         directory: directory, output: output, timeout: timeout)
    }

    private static func spawn(executable: URL, arguments: [String], environment: [String: String],
                               directory: URL, output: URL, timeout: TimeInterval) throws -> Data {
        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        #else
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        #endif
        guard posix_spawn_file_actions_init(&actions) == 0,
              posix_spawnattr_init(&attributes) == 0 else { throw UsageError.commandFailed }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        guard posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, output.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600) == 0,
              posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, directory.path) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else { throw UsageError.commandFailed }
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }
        var pid: pid_t = 0
        let result = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&pid, executable.path, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        guard result == 0 else { throw UsageError.commandFailed }
        var reaped = false
        defer {
            // Only this invocation's process group. Also clean up children on successful exit.
            kill(-pid, SIGKILL)
            if !reaped { var status: Int32 = 0; _ = waitpid(pid, &status, 0) }
        }
        let started = ProcessInfo.processInfo.systemUptime
        while true {
            try Task.checkCancellation()
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
            guard size <= 1_048_576 else { throw UsageError.outputTooLarge }
            var status: Int32 = 0
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid {
                reaped = true
                guard status == 0 else { throw UsageError.commandFailed }
                let data = try Data(contentsOf: output)
                guard data.count <= 1_048_576 else { throw UsageError.outputTooLarge }
                return data
            }
            if waited == -1, errno != EINTR { throw UsageError.commandFailed }
            guard ProcessInfo.processInfo.systemUptime - started < timeout else { throw UsageError.timedOut }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
