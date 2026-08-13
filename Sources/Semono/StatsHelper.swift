import Foundation
import os

/// Persistent client for the bundled `stats_helper` subprocess. A single
/// resident process serves GPU / power / disk readings over a line protocol
/// (request line in, response line out), replacing the previous per-tick
/// process spawns.
///
/// Requests are serialized (the sampler awaits each one). A request that
/// does not answer within the timeout terminates the helper; the next query
/// respawns it, so a hung helper recovers by itself. Responses arrive
/// through the pipe's readability handler; the request write is a single
/// short pipe write performed while holding the lock, so a timeout firing
/// mid-write cannot tear the request down first.
///
/// All state is guarded by `lock`. The readability handler is dispatched on
/// its own queue and may interleave with request submission, so it captures
/// the process it belongs to and only mutates state while that process is
/// still the current one — a late EOF from a replaced helper cannot clobber
/// a newer helper's pipes or steal its pending request.
final class StatsHelper: @unchecked Sendable {
    static let shared = StatsHelper()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.semono.app.statshelper", qos: .utility)
    private var process: Process?
    private var writeHandle: FileHandle?
    private var readHandle: FileHandle?
    private var pending: CheckedContinuation<String, Never>?
    private var pendingTimer: DispatchSourceTimer?
    /// Identity of the in-flight request (CheckedContinuation is a struct, so
    /// ownership cannot be compared by identity). Lets the cancellation
    /// handler and the post-registration re-check tell "our" request apart
    /// from one that was already claimed or replaced.
    private var pendingToken: QueryToken?
    /// Command word the in-flight request is waiting for. Responses echo it,
    /// so a late line from a cancelled request is dropped instead of being
    /// attributed to the newer request.
    private var pendingCommand: String?
    private var buffer = Data()
    private let logger = Logger(subsystem: "com.semono.app", category: "stats_helper")
    private var warnedSpawn = false
    private var warnedHang = false
    /// When the helper died (crash, kill, EOF). A fresh death suppresses
    /// respawns for a short backoff so a helper that dies on launch is not
    /// respawned — and logged about — on every tick.
    private var lastHelperDeath: Date?
    private static let respawnBackoff: TimeInterval = 10

    private init() {}

    /// Runs `body` with `lock` held and always unlocks, so no early-return
    /// path can forget the pairing.
    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Sends one request line and returns the response line. Returns ""
    /// when the helper cannot be launched, times out, dies, or the calling
    /// task is cancelled.
    func query(_ name: String, timeout: TimeInterval = 2.0) async -> String {
        let token = QueryToken()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                /// What to do once the lock is released; the continuation is
                /// always resumed exactly once, after the lock is dropped.
                enum Outcome {
                    case registered   // request written; the response or timeout resumes
                    case rejected     // resume "" now
                    case writeFailed(Process, DispatchSourceTimer) // kill helper, resume ""
                }

                let outcome: Outcome = withLock {
                    if process == nil || !(process?.isRunning ?? false) {
                        if let death = lastHelperDeath,
                           Date().timeIntervalSince(death) < Self.respawnBackoff {
                            // The helper just died; skip the spawn this tick.
                            return .rejected
                        }
                        spawnLocked()
                    }
                    guard let proc = process, proc.isRunning, pending == nil else {
                        if process == nil {
                            warnOnce(flag: &warnedSpawn,
                                     message: "stats_helper could not be launched; GPU/power/disk will read 0")
                        }
                        return .rejected
                    }
                    pending = cont
                    pendingToken = token
                    pendingCommand = name

                    let timer = DispatchSource.makeTimerSource(queue: queue)
                    timer.schedule(deadline: .now() + timeout)
                    timer.setEventHandler { [weak self, weak timer] in
                        guard let timer else { return }
                        self?.handleTimeout(timer: timer)
                    }
                    pendingTimer = timer
                    timer.resume()

                    // The cancellation handler may have run before the
                    // continuation was registered; re-check so a cancelled task
                    // never stays suspended until the timeout. If the handler
                    // already claimed the request (token gone), it also resumed
                    // the continuation — do not resume twice.
                    guard !Task.isCancelled else {
                        if pendingToken === token {
                            pending = nil
                            pendingToken = nil
                            pendingCommand = nil
                            pendingTimer = nil
                            timer.cancel()
                            return .rejected
                        }
                        return .registered
                    }

                    // The write happens under the lock so a timeout firing
                    // mid-write cannot tear the request down first.
                    do {
                        try writeHandle?.write(contentsOf: Data((name + "\n").utf8))
                        return .registered
                    } catch {
                        // The helper died between the running check and the write.
                        // Drop the request and the timer; kill the helper so the
                        // EOF handler frees the pipe state, and the next query
                        // respawns a fresh process.
                        pendingTimer = nil
                        pending = nil
                        pendingToken = nil
                        pendingCommand = nil
                        return .writeFailed(proc, timer)
                    }
                }

                switch outcome {
                case .registered:
                    break
                case .rejected:
                    cont.resume(returning: "")
                case .writeFailed(let proc, let timer):
                    timer.cancel()
                    killHelper(proc)
                    cont.resume(returning: "")
                }
            }
        } onCancel: {
            // Resumes an in-flight request promptly when the caller is
            // cancelled instead of leaving the task suspended until the
            // timeout. Only claims the request while it is still ours. The
            // helper is left running: its late response is dropped (pending
            // is nil), so the line protocol stays in sync.
            let claimed: (timer: DispatchSourceTimer?, cont: CheckedContinuation<String, Never>?)? = withLock {
                guard pendingToken === token else { return nil }
                let cont = pending
                pending = nil
                pendingToken = nil
                pendingCommand = nil
                let timer = pendingTimer
                pendingTimer = nil
                return (timer, cont)
            }
            claimed?.timer?.cancel()
            claimed?.cont?.resume(returning: "")
        }
    }

    /// Kills the helper so no orphan remains after the app quits. Resumes
    /// any in-flight request with "".
    func shutdown() {
        let (proc, timer, cont): (Process?, DispatchSourceTimer?, CheckedContinuation<String, Never>?) = withLock {
            let proc = process
            process = nil
            if let h = readHandle { h.readabilityHandler = nil }
            readHandle = nil
            writeHandle = nil
            buffer = Data()
            let cont = pending
            pending = nil
            pendingToken = nil
            pendingCommand = nil
            let timer = pendingTimer
            pendingTimer = nil
            return (proc, timer, cont)
        }
        timer?.cancel()
        killHelper(proc)
        cont?.resume(returning: "")
    }

    /// Timeout path: abandon the request and kill the helper. The EOF
    /// handler observes the termination and frees the pipe state. A stale
    /// timer (a response arrived first, or a newer request owns the slot)
    /// is ignored.
    private func handleTimeout(timer: DispatchSourceTimer) {
        var proc: Process?
        var cont: CheckedContinuation<String, Never>?
        var alive = false
        withLock {
            guard pendingTimer === timer else { return }
            pendingTimer = nil
            proc = process
            cont = pending
            alive = (proc?.isRunning ?? false) && cont != nil
            if alive {
                pending = nil
                pendingToken = nil
                pendingCommand = nil
                warnOnce(flag: &warnedHang,
                         message: "stats_helper did not answer in time; restarting it")
            }
        }
        timer.cancel()
        guard alive else { return }
        killHelper(proc)
        cont?.resume(returning: "")
    }

    /// Result of processing one chunk of pipe data under the lock. Actions
    /// that touch the outside world (timer cancel, continuation resume) run
    /// after the lock is released.
    private enum ReadResult {
        case ignore
        case eof(CheckedContinuation<String, Never>?, DispatchSourceTimer?)
        case line(String, CheckedContinuation<String, Never>?, DispatchSourceTimer?)
    }

    private func spawnLocked() {
        if let h = readHandle { h.readabilityHandler = nil }
        readHandle = nil
        writeHandle = nil
        buffer = Data()

        let name = "stats_helper"
        var url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(name)")
        if !FileManager.default.fileExists(atPath: url.path) {
            // Debug runs (`swift run`) place the helper next to the executable.
            url = Bundle.main.bundleURL.appendingPathComponent(name)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            process = nil
            return
        }

        let task = Process()
        task.executableURL = url
        let out = Pipe()
        let input = Pipe()
        task.standardOutput = out
        task.standardInput = input
        do {
            try task.run()
        } catch {
            process = nil
            return
        }

        process = task
        // Foundation's Process reaps the child itself on exit, so no
        // termination handler is needed.
        writeHandle = input.fileHandleForWriting
        readHandle = out.fileHandleForReading
        readHandle?.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            let result: ReadResult = self.withLock {
                if data.isEmpty {
                    // EOF: the helper died (or was terminated). Only tear down
                    // if this handle still belongs to the current process; a
                    // stale EOF from a replaced helper must not disturb the
                    // newer one or its pending request.
                    guard let proc = self.process, proc === task else {
                        return .ignore
                    }
                    self.lastHelperDeath = Date()
                    handle.readabilityHandler = nil
                    self.process = nil
                    self.readHandle = nil
                    self.writeHandle = nil
                    self.buffer = Data()
                    let cont = self.pending
                    self.pending = nil
                    self.pendingToken = nil
                    self.pendingCommand = nil
                    let timer = self.pendingTimer
                    self.pendingTimer = nil
                    return .eof(cont, timer)
                }
                self.buffer.append(data)
                guard let nl = self.buffer.firstIndex(of: 0x0A) else {
                    return .ignore
                }
                let line = String(data: Data(self.buffer[..<nl]), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.buffer = Data(self.buffer[(nl + 1)...])
                // A real response means the helper is healthy again; re-arm
                // the once-only warnings for a future failure episode.
                self.warnedSpawn = false
                self.warnedHang = false
                // Responses echo the request word; a line from a request that
                // was already cancelled belongs to nobody — drop it and keep
                // waiting for the current request's line.
                guard let space = line.firstIndex(of: " "),
                      let command = self.pendingCommand,
                      line[..<space] == command else {
                    return .ignore
                }
                let payload = String(line[line.index(after: space)...])
                let cont = self.pending
                self.pending = nil
                self.pendingToken = nil
                self.pendingCommand = nil
                let timer = self.pendingTimer
                self.pendingTimer = nil
                return .line(payload, cont, timer)
            }
            switch result {
            case .ignore:
                break
            case .eof(let cont, let timer):
                timer?.cancel()
                cont?.resume(returning: "")
            case .line(let payload, let cont, let timer):
                timer?.cancel()
                cont?.resume(returning: payload)
            }
        }
    }

    /// Terminates the helper; Foundation's Process reaps it on exit.
    private func killHelper(_ proc: Process?) {
        guard let proc, proc.isRunning else { return }
        proc.terminate()
    }

    /// Reference-type identity token for an in-flight request; see
    /// `pendingToken`. Carries no data, so it is safe to send across
    /// isolation domains.
    private final class QueryToken: @unchecked Sendable {}

    private func warnOnce(flag: inout Bool, message: String) {
        guard !flag else { return }
        flag = true
        logger.error("\(message, privacy: .public)")
    }
}
