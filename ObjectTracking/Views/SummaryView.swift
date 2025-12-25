import SwiftUI
import RealityKit
import UniformTypeIdentifiers

struct SummaryView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var selectedSummary: SummaryType?
    @State private var isExportingCSV = false
    @State private var csvURL: URL?

    enum SummaryType: Int, Identifiable, CaseIterable {
        case straight1, straight2, straight3, straight4, zigzagBeginner, zigzagAdvanced
        
        var id: Int { rawValue }
    }
    
    private func headsetPos(for type: SummaryType) -> SIMD3<Float>? {
        switch type {
        case .straight1: return dataManager.straight1HeadsetPosition
        case .straight2: return dataManager.straight2HeadsetPosition
        case .straight3: return dataManager.straight3HeadsetPosition
        case .straight4: return dataManager.straight4HeadsetPosition
        case .zigzagBeginner: return dataManager.zigzagBeginnerHeadsetPosition
        case .zigzagAdvanced: return dataManager.zigzagAdvancedHeadsetPosition
        }
    }

    private func objectPos(for type: SummaryType) -> SIMD3<Float>? {
        switch type {
        case .straight1: return dataManager.straight1ObjectPosition
        case .straight2: return dataManager.straight2ObjectPosition
        case .straight3: return dataManager.straight3ObjectPosition
        case .straight4: return dataManager.straight4ObjectPosition
        case .zigzagBeginner: return dataManager.zigzagBeginnerObjectPosition
        case .zigzagAdvanced: return dataManager.zigzagAdvancedObjectPosition
        }
    }

    var body: some View {
        VStack {
            Text("Thank You")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.5), value: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
        .onAppear {
            // Automatically export all data when summary view appears
            exportAllDataToDocuments()
        }
       }

    private func userTrace(for type: SummaryType) -> [SIMD3<Float>] {
        switch type {
        case .straight1: return dataManager.straight1UserTrace.map { $0.0 }
        case .straight2: return dataManager.straight2UserTrace.map { $0.0 }
        case .straight3: return dataManager.straight3UserTrace.map { $0.0 }
        case .straight4: return dataManager.straight4UserTrace.map { $0.0 }
        case .zigzagBeginner: return dataManager.zigzagBeginnerUserTrace.map { $0.0 }
        case .zigzagAdvanced: return dataManager.zigzagAdvancedUserTrace.map { $0.0 }
        }
    }

    private func exportStraightPathDots(for type: SummaryType) {
        guard let start = headsetPos(for: type), let end = objectPos(for: type) else { return }
        let dots = generateStraightLineGuideDots(start: start, end: end)
        
        var csvString = "X,Y,Z\n"
        for dot in dots {
            csvString += "\(dot.x),\(dot.y),\(dot.z)\n"
        }
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("\(type.rawValueFilenamePrefix)GuideDots.csv")
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            csvURL = fileURL
            isExportingCSV = true
        } catch {
            // Handle error if needed
        }
    }
    
    private func exportStraightUserTrace(for type: SummaryType) {
        let trace: [(SIMD3<Float>, TimeInterval)]
        switch type {
        case .straight1: trace = dataManager.straight1UserTrace
        case .straight2: trace = dataManager.straight2UserTrace
        case .straight3: trace = dataManager.straight3UserTrace
        case .straight4: trace = dataManager.straight4UserTrace
        default: return
        }
        guard !trace.isEmpty else { return }
        var csvString = "X,Y,Z\n"
        for point in trace {
            csvString += "\(point.0.x),\(point.0.y),\(point.0.z)\n"
        }
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("\(type.rawValueFilenamePrefix)UserTrace.csv")
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            csvURL = fileURL
            isExportingCSV = true
        } catch {
            // Handle error if needed
        }
    }
    
    private func exportZigzagBeginnerPathDots() {
        guard let start = headsetPos(for: .zigzagBeginner), let end = objectPos(for: .zigzagBeginner) else { return }
        let dots = generateStraightLineGuideDots(start: start, end: end)
        
        var csvString = "X,Y,Z\n"
        for dot in dots {
            csvString += "\(dot.x),\(dot.y),\(dot.z)\n"
        }
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("ZigzagBeginnerGuideDots.csv")
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            csvURL = fileURL
            isExportingCSV = true
        } catch {
            // Handle error if needed
        }
    }
    
    private func exportZigzagBeginnerUserTrace() {
        let trace = dataManager.zigzagBeginnerUserTrace
        guard !trace.isEmpty else { return }
        var csvString = "X,Y,Z\n"
        for point in trace {
            csvString += "\(point.0.x),\(point.0.y),\(point.0.z)\n"
        }
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("ZigzagBeginnerUserTrace.csv")
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            csvURL = fileURL
            isExportingCSV = true
        } catch {
            // Handle error if needed
        }
    }
    
    private func exportZigzagAdvancedPathDots() {
        guard let start = headsetPos(for: .zigzagAdvanced), let end = objectPos(for: .zigzagAdvanced) else { return }
        let dots = generateStraightLineGuideDots(start: start, end: end)
        
        var csvString = "X,Y,Z\n"
        for dot in dots {
            csvString += "\(dot.x),\(dot.y),\(dot.z)\n"
        }
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("ZigzagAdvancedGuideDots.csv")
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            csvURL = fileURL
            isExportingCSV = true
        } catch {
            // Handle error if needed
        }
    }
    
    private func exportZigzagAdvancedUserTrace() {
        let trace = dataManager.zigzagAdvancedUserTrace
        guard !trace.isEmpty else { return }
        var csvString = "X,Y,Z\n"
        for point in trace {
            csvString += "\(point.0.x),\(point.0.y),\(point.0.z)\n"
        }
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("ZigzagAdvancedUserTrace.csv")
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            csvURL = fileURL
            isExportingCSV = true
        } catch {
            // Handle error if needed
        }
    }

    private func exportAllData() {
        var rows: [String] = ["task,path_type,attempt_number,point_idx,timestamp,x,y,z"]

        func appendGuide(task: String, points: [SIMD3<Float>]) {
            for (i, p) in points.enumerated() {
                rows.append("\(task),guide,,\(i),,\(p.x),\(p.y),\(p.z)")
            }
        }

        func appendUserAttempt(task: String, attemptNumber: Int, trace: [TraceAttempt.TrackedPoint]) {
            for (i, point) in trace.enumerated() {
                rows.append("\(task),user,\(attemptNumber),\(i),\(point.timestamp),\(point.x),\(point.y),\(point.z)")
            }
        }
        
        // Process all task types
        let allTaskTypes: [SummaryType] = [.straight1, .straight2, .straight3, .straight4, .zigzagBeginner, .zigzagAdvanced]
        
        for taskType in allTaskTypes {
            let taskName = taskType.rawValueFilenamePrefix
            
            // Add guide dots first
            if let start = headsetPos(for: taskType), let end = objectPos(for: taskType) {
                let guideDots: [SIMD3<Float>]
                
                switch taskType {
                case .zigzagBeginner:
                    guideDots = generateZigZagGuideDots(start: start, end: end, amplitude: 0.05, frequency: 2)
                case .zigzagAdvanced:
                    guideDots = generateZigZagGuideDots(start: start, end: end, amplitude: 0.05, frequency: 4)
                default:
                    guideDots = generateStraightLineGuideDots(start: start, end: end)
                }
                
                appendGuide(task: taskName, points: guideDots)
            }
            
            // Add all user attempts (1-10) for this task
            let attempts = dataManager.getAttempts(for: stepFromSummaryType(taskType))
            for attempt in attempts {
                appendUserAttempt(task: taskName, attemptNumber: attempt.attemptNumber, trace: attempt.userTrace)
            }
        }

        let csv = rows.joined(separator: "\n")
        guard rows.count > 1 else { return }

        do {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("AllExportedData.csv")
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            csvURL = fileURL
            isExportingCSV = true
        } catch {
        }
    }
    
    private func exportAllDataToDocuments() {
        var rows: [String] = ["task,path_type,attempt_number,point_idx,timestamp,x,y,z"]

        func appendGuide(task: String, points: [SIMD3<Float>]) {
            for (i, p) in points.enumerated() {
                rows.append("\(task),guide,,\(i),,\(p.x),\(p.y),\(p.z)")
            }
        }

        func appendUserAttempt(task: String, attemptNumber: Int, trace: [TraceAttempt.TrackedPoint]) {
            for (i, point) in trace.enumerated() {
                rows.append("\(task),user,\(attemptNumber),\(i),\(point.timestamp),\(point.x),\(point.y),\(point.z)")
            }
        }
        
        // Process all task types
        let allTaskTypes: [SummaryType] = [.straight1, .straight2, .straight3, .straight4, .zigzagBeginner, .zigzagAdvanced]
        
        for taskType in allTaskTypes {
            let taskName = taskType.rawValueFilenamePrefix
            
            // Add guide dots first
            if let start = headsetPos(for: taskType), let end = objectPos(for: taskType) {
                let guideDots: [SIMD3<Float>]
                
                switch taskType {
                case .zigzagBeginner:
                    guideDots = generateZigZagGuideDots(start: start, end: end, amplitude: 0.05, frequency: 2)
                case .zigzagAdvanced:
                    guideDots = generateZigZagGuideDots(start: start, end: end, amplitude: 0.05, frequency: 4)
                default:
                    guideDots = generateStraightLineGuideDots(start: start, end: end)
                }
                
                appendGuide(task: taskName, points: guideDots)
            }
            
            // Add all user attempts (1-10) for this task
            let attempts = dataManager.getAttempts(for: stepFromSummaryType(taskType))
            for attempt in attempts {
                appendUserAttempt(task: taskName, attemptNumber: attempt.attemptNumber, trace: attempt.userTrace)
            }
        }

        let csv = rows.joined(separator: "\n")
        guard rows.count > 1 else { return }

        do {
            // Save to Documents directory for easy access via Files app
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let timestamp = DateFormatter.iso8601.string(from: Date())
            let filename = "HandEyeCoordinationData_\(timestamp).csv"
            let fileURL = documentsPath.appendingPathComponent(filename)
            
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Data successfully exported to Documents: \(fileURL.path)")
        } catch {
            print("Error exporting data to Documents: \(error)")
        }
    }
    
    private func stepFromSummaryType(_ summaryType: SummaryType) -> Step {
        switch summaryType {
        case .straight1: return .straight1
        case .straight2: return .straight2
        case .straight3: return .straight3
        case .straight4: return .straight4
        case .zigzagBeginner: return .zigzagBeginner
        case .zigzagAdvanced: return .zigzagAdvanced
        }
    }

    
    func generateStraightLineGuideDots(start: SIMD3<Float>, end: SIMD3<Float>) -> [SIMD3<Float>] {
        let dotSpacing: Float = 0.001
        let maxDots = 1000
        let lineVector = end - start
        let lineLength = length(lineVector)
        if lineLength == 0 {
            return [start]
        }
        let direction = normalize(lineVector)
        let numberOfSegments = min(Int(lineLength / dotSpacing), maxDots)
        var dots: [SIMD3<Float>] = []
        dots.reserveCapacity(numberOfSegments + 1)
        for i in 0...numberOfSegments {
            dots.append(start + direction * (Float(i) * dotSpacing))
        }
        if dots.last != end {
            dots.append(end)
        }
        return dots
    }
    
    func generateZigZagGuideDots(start: SIMD3<Float>, end: SIMD3<Float>, amplitude: Float, frequency: Int, dotSpacing: Float = 0.001, maxDots: Int = 1000) -> [SIMD3<Float>] {
        let lineVector = end - start
        let lineLength = simd_length(lineVector)
        let computedDotCount = Int(lineLength / dotSpacing)
        let dotCount = min(maxDots - 1, computedDotCount)
        guard dotCount > 0 else { return [start, end] }
        let direction = simd_normalize(lineVector)
        let up: SIMD3<Float> = abs(direction.y) < 0.99 ? [0, 1, 0] : [1, 0, 0]
        let right = simd_normalize(simd_cross(direction, up))
        var points: [SIMD3<Float>] = []
        for i in 0...dotCount {
            let t = Float(i) / Float(dotCount)
            let point = start + direction * (lineLength * t)
            let phase = Float(i) * Float(frequency) * .pi / Float(dotCount)
            let amp = (i == 0 || i == dotCount) ? 0 : amplitude * sin(phase)
            let offset = right * amp
            points.append(point + offset)
        }
        return points
    }
}

private struct URLDocument: FileDocument {
    let fileURL: URL

    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        throw NSError(domain: "Not supported", code: -1, userInfo: nil)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return try FileWrapper(url: fileURL, options: .immediate)
    }
}

extension SummaryView.SummaryType {
    var rawValueFilenamePrefix: String {
        switch self {
        case .straight1: return "straight1"
        case .straight2: return "straight2"
        case .straight3: return "straight3"
        case .straight4: return "straight4"
        case .zigzagBeginner: return "zigzag_beginner"
        case .zigzagAdvanced: return "zigzag_advanced"
        }
    }
    
    var buttonTitle: String {
        switch self {
        case .straight1: return "Straight 1"
        case .straight2: return "Straight 2"
        case .straight3: return "Straight 3"
        case .straight4: return "Straight 4"
        case .zigzagBeginner: return "Zigzag Beginner"
        case .zigzagAdvanced: return "Zigzag Advanced"
        }
    }
}
