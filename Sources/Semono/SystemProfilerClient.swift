import Foundation

enum SystemProfilerError: LocalizedError {
    case launchFailed(String)
    case failed(Int32)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "system_profiler could not be launched: \(message)"
        case .failed(let status):
            return "system_profiler exited with status \(status)."
        case .timedOut:
            return "system_profiler did not answer in time."
        }
    }
}

/// Runs `system_profiler -json <dataType>` off the main thread, with a
/// watchdog and cooperative cancellation. The JSON is decoded into the
/// immutable display tree before it leaves this type, so the main actor only
/// ever receives `Sendable` values.
enum SystemProfilerClient {
    private static let timeout: Duration = .seconds(30)

    static func report(for category: DeviceCategory) async throws -> DeviceReport {
        let data = try await json(for: category)
        let fetchedAt = Date()
        return try await Task.detached(priority: .userInitiated) {
            try SystemProfilerReportBuilder.build(category: category, json: data, now: fetchedAt)
        }.value
    }

    private static func json(for category: DeviceCategory) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await run(dataType: category.dataType)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw SystemProfilerError.timedOut
            }
            do {
                guard let data = try await group.next() else {
                    throw SystemProfilerError.failed(-1)
                }
                group.cancelAll()
                return data
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private static func run(dataType: String) async throws -> Data {
        let box = SystemProfilerProcess(dataType: dataType)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        try box.process.run()
                        if Task.isCancelled {
                            box.terminate()
                        }
                        let data = box.output.fileHandleForReading.readDataToEndOfFile()
                        box.process.waitUntilExit()

                        if Task.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else if box.process.terminationStatus == 0 {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: SystemProfilerError.failed(box.process.terminationStatus))
                        }
                    } catch {
                        continuation.resume(throwing: SystemProfilerError.launchFailed(error.localizedDescription))
                    }
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}

/// `Process` and `Pipe` are reference types shared with a background queue and
/// the cancellation handler. The box keeps that sharing explicit; only
/// `terminate` touches the process from outside the worker queue, and
/// `Process.terminate()` is safe to call repeatedly.
private final class SystemProfilerProcess: @unchecked Sendable {
    let process = Process()
    let output = Pipe()

    init(dataType: String) {
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", dataType]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }
}
