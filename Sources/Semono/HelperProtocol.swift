import Foundation

/// Line protocol shared by the app and `stats_helper`.
///
/// Request:   `<id> <command>`
/// Response:  `<id> <command> <protocol-version> <value...>`
///
/// Values are either decimal numbers or `na`. The id makes a response from a
/// cancelled request distinguishable from the answer to the next request, even
/// when the command word is identical. The protocol version lets the app fail
/// loudly instead of silently parsing an old helper's response as zeros.
enum HelperProtocol {
    static let version = 2

    static func request(id: UInt64, command: String) -> String {
        "\(id) \(command)\n"
    }

    struct Response: Equatable, Sendable {
        let id: UInt64
        let command: String
        let payload: String
    }

    /// Parses one complete response line. Returns nil for malformed lines,
    /// an unsupported protocol version, or a missing envelope.
    static func parseResponse(_ line: String) -> Response? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3,
              let id = UInt64(parts[0]),
              Int(parts[2]) == version
        else { return nil }

        return Response(
            id: id,
            command: String(parts[1]),
            payload: parts.dropFirst(3).joined(separator: " ")
        )
    }

    /// Splits a payload into exactly `count` tokens, treating `na` as a
    /// value placeholder. Returns nil on a malformed field count.
    static func fields(_ payload: String, count: Int) -> [String]? {
        let parts = payload.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        return parts.count == count ? parts : nil
    }

    static func double(_ token: String) -> Double? {
        token == "na" ? nil : Double(token)
    }

    static func uint64(_ token: String) -> UInt64? {
        token == "na" ? nil : UInt64(token)
    }
}

/// Buffers pipe data and yields complete newline-delimited lines. A single
/// readability callback can contain a stale response and the current one;
/// consuming only the first line would leave the current answer stuck until
/// the request times out.
struct LineBuffer: Sendable {
    private var data = Data()

    mutating func append(_ chunk: Data) {
        data.append(chunk)
    }

    mutating func nextLine() -> String? {
        guard let newline = data.firstIndex(of: 0x0A) else { return nil }
        let line = String(decoding: data[..<newline], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        data = Data(data[(newline + 1)...])
        return line
    }

    mutating func reset() {
        data = Data()
    }
}
