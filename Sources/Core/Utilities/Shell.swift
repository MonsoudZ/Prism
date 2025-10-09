import Foundation

/// Tiny helper for running short code snippets for multiple languages.
/// NOTE: This is for local dev convenience, not a hardened sandbox.
enum Shell {

    // MARK: Public API expected by callers (returns a String)
    /// Runs `code` for the chosen language label and returns stdout (or stderr/exit code on error).
    static func runCode(_ languageLabel: String, code: String) -> String {
        // Map UI label -> executable + arg strategy
        let map: [String: (cmd: String, args: [String], needsFile: Bool, ext: String)] = [
            "Python":      ("python3", ["-"], false, "py"),
            "Ruby":        ("ruby",    ["-e", code], false, "rb"),
            "Node.js":     ("node",    ["-e", code], false, "js"),
            "JavaScript":  ("node",    ["-e", code], false, "js"),
            "Swift":       ("swift",   [],  true,  "swift"),
            "Bash":        ("bash",    ["-c", code], false, "sh"),
            "Go":          ("go",      ["run"], true, "go"),
            "C":           ("bash",    ["-lc"], true, "c"),
            "C++":         ("bash",    ["-lc"], true, "cpp"),
            "Rust":        ("bash",    ["-lc"], true, "rs"),
            "Java":        ("bash",    ["-lc"], true, "java"),
            "SQL":         ("sqlite3", [], true, "sql")
        ]

        guard let entry = map[languageLabel] else {
            return "Unsupported language: \(languageLabel)"
        }

        // Prepare arguments; some languages need a temporary file
        var args = entry.args
        var cleanup: (() -> Void)?

        if entry.needsFile {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("prism-\(UUID().uuidString).\(entry.ext)")

            do {
                try code.write(to: tmp, atomically: true, encoding: .utf8)
            } catch {
                return "Failed to write temp file: \(error.localizedDescription)"
            }

            cleanup = { try? FileManager.default.removeItem(at: tmp) }

            switch languageLabel {
            case "Swift", "Go", "SQL":
                // Executable reads file path as argument
                args.append(tmp.path)

            case "C":
                // Compile from stdin and run the produced binary
                let bin = tmp.deletingPathExtension().path
                args = ["-lc", "cat '\(tmp.path)' | gcc -x c -o '\(bin)' - && '\(bin)'"]
            case "C++":
                let bin = tmp.deletingPathExtension().path
                args = ["-lc", "cat '\(tmp.path)' | g++ -x c++ -o '\(bin)' - && '\(bin)'"]
            case "Rust":
                let bin = tmp.deletingPathExtension().path
                args = ["-lc", "cat '\(tmp.path)' | rustc -o '\(bin)' - && '\(bin)'"]
            case "Java":
                // Simple one-file runner
                let dir = tmp.deletingLastPathComponent().path
                args = ["-lc", "cd '\(dir)' && cat '\(tmp.lastPathComponent)' > Main.java && javac Main.java && java Main"]
            default:
                args.append(tmp.path)
            }
        }

        defer { cleanup?() }

        // If the tool expects code on stdin (e.g. python3 -), provide it; else input is nil
        let stdinData: Data? = (entry.needsFile || expectsInlineCode(languageLabel)) ? nil : code.data(using: .utf8)

        let result = run("/usr/bin/env", arguments: [entry.cmd] + args, stdin: stdinData)

        if result.exitCode == 0 {
            return result.output.isEmpty ? "(no output)" : result.output
        } else {
            if !result.output.isEmpty { return result.output }          // some tools write errors to stdout
            if !result.error.isEmpty { return result.error }            // otherwise stderr
            return "Exited with code \(result.exitCode)"
        }
    }

    // MARK: - Private helpers

    /// Launches a process, optionally writing `stdin` to its standard input.
    private static func run(_ launchPath: String, arguments: [String], stdin: Data?) -> (output: String, error: String, exitCode: Int32) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError  = err

        var inPipe: Pipe?
        if let stdin = stdin {
            let p = Pipe()
            inPipe = p
            task.standardInput = p
            p.fileHandleForWriting.write(stdin)
            try? p.fileHandleForWriting.close()
        }

        do {
            try task.run()
        } catch {
            return ("", "Failed to start process: \(error.localizedDescription)", 1)
        }

        task.waitUntilExit()

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        // Clean up input pipe if any
        if let p = inPipe {
            try? p.fileHandleForReading.close()
        }

        return (stdout, stderr, task.terminationStatus)
    }

    /// Languages that we mapped with inline `-e` already include the code in arguments,
    /// so they do NOT need stdin.
    private static func expectsInlineCode(_ label: String) -> Bool {
        switch label {
        case "Ruby", "Node.js", "JavaScript", "Bash":
            return true
        default:
            return false
        }
    }
}
