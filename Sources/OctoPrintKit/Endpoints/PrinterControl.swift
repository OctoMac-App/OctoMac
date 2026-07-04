import Foundation

// Printer and job operations.
// https://docs.octoprint.org/en/main/api/printer.html
// https://docs.octoprint.org/en/main/api/job.html

public enum Axis: String, Sendable, CaseIterable {
    case x, y, z
}

extension OctoPrintClient {
    // MARK: State

    public func printerStatus(history: Bool = false, limit: Int? = nil, exclude: [String] = []) async throws -> PrinterStatus {
        var query: [URLQueryItem] = []
        if history { query.append(URLQueryItem(name: "history", value: "true")) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if !exclude.isEmpty { query.append(URLQueryItem(name: "exclude", value: exclude.joined(separator: ","))) }
        return try await get("api/printer", query: query)
    }

    /// Last printer error (OctoPrint 1.10+). Returns raw JSON as the shape is still evolving.
    public func printerError() async throws -> JSONValue {
        try await get("api/printer/error")
    }

    // MARK: Job

    public func job() async throws -> JobStatus {
        try await get("api/job")
    }

    public func job(_ command: JobCommand) async throws {
        try await post("api/job", body: command.body)
    }

    // MARK: Print head

    public func jog(x: Double? = nil, y: Double? = nil, z: Double? = nil, absolute: Bool = false, speed: Double? = nil) async throws {
        var body: CommandBody = ["command": "jog", "absolute": .bool(absolute)]
        if let x { body["x"] = JSONValue(x) }
        if let y { body["y"] = JSONValue(y) }
        if let z { body["z"] = JSONValue(z) }
        if let speed { body["speed"] = JSONValue(speed) }
        try await post("api/printer/printhead", body: body)
    }

    public func home(_ axes: [Axis] = Axis.allCases) async throws {
        try await post("api/printer/printhead", body: ["command": "home", "axes": JSONValue(axes.map(\.rawValue))] as CommandBody)
    }

    /// Feed rate factor in percent (50–200).
    public func setFeedRate(_ percent: Int) async throws {
        try await post("api/printer/printhead", body: ["command": "feedrate", "factor": JSONValue(percent)] as CommandBody)
    }

    // MARK: Tools

    public func setToolTargets(_ targets: [String: Double]) async throws {
        try await post("api/printer/tool", body: ["command": "target", "targets": .object(targets.mapValues { JSONValue.number($0) })] as CommandBody)
    }

    public func setToolOffsets(_ offsets: [String: Double]) async throws {
        try await post("api/printer/tool", body: ["command": "offset", "offsets": .object(offsets.mapValues { JSONValue.number($0) })] as CommandBody)
    }

    public func selectTool(_ tool: String) async throws {
        try await post("api/printer/tool", body: ["command": "select", "tool": .string(tool)] as CommandBody)
    }

    /// Extrudes (positive) or retracts (negative) the given amount in mm on the current tool.
    public func extrude(_ amount: Double, speed: Double? = nil) async throws {
        var body: CommandBody = ["command": "extrude", "amount": JSONValue(amount)]
        if let speed { body["speed"] = JSONValue(speed) }
        try await post("api/printer/tool", body: body)
    }

    /// Flow rate factor in percent (75–125).
    public func setFlowRate(_ percent: Int) async throws {
        try await post("api/printer/tool", body: ["command": "flowrate", "factor": JSONValue(percent)] as CommandBody)
    }

    // MARK: Bed & chamber

    public func setBedTarget(_ target: Double) async throws {
        try await post("api/printer/bed", body: ["command": "target", "target": JSONValue(target)] as CommandBody)
    }

    public func setBedOffset(_ offset: Double) async throws {
        try await post("api/printer/bed", body: ["command": "offset", "offset": JSONValue(offset)] as CommandBody)
    }

    public func setChamberTarget(_ target: Double) async throws {
        try await post("api/printer/chamber", body: ["command": "target", "target": JSONValue(target)] as CommandBody)
    }

    /// Sets the target for any heater key reported by OctoPrint (`tool0`, `bed`, `chamber`, ...).
    public func setTarget(_ target: Double, forHeater key: String) async throws {
        switch HeaterKind(key: key) {
        case .bed: try await setBedTarget(target)
        case .chamber: try await setChamberTarget(target)
        case .tool, .other, .ambient, .probe: try await setToolTargets([key: target])
        }
    }

    // MARK: SD card

    public func sdState() async throws -> SDState {
        try await get("api/printer/sd")
    }

    public func sd(_ command: String) async throws {
        precondition(["init", "refresh", "release"].contains(command))
        try await post("api/printer/sd", body: ["command": .string(command)] as CommandBody)
    }

    // MARK: Arbitrary G-code

    public func sendGcode(_ commands: [String]) async throws {
        try await post("api/printer/command", body: ["commands": JSONValue(commands)] as CommandBody)
    }

    public func sendGcode(_ command: String) async throws {
        try await sendGcode(command.split(whereSeparator: \.isNewline).map(String.init))
    }

    /// Custom control definitions configured on the server (`GET /api/printer/command/custom`).
    public func customControls() async throws -> JSONValue {
        try await get("api/printer/command/custom")
    }
}
