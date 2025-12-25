//
//  DataManager.swift
//  ObjectTracking
//
//  Created by Interactive 3D Design on 24/7/25.
//  Copyright © 2025 Apple. All rights reserved.
//

import SwiftUI
import simd

enum Step {
    case straight1
    case straight2
    case straight3
    case straight4
    case zigzagBeginner
    case zigzagAdvanced
}

struct TraceAttempt: Codable {
    let attemptNumber: Int
    let timestamp: Date
    let userTrace: [TrackedPoint]
    let headsetPosition: TrackedPoint?
    let objectPosition: TrackedPoint?
    let totalTraceLength: Float
    let maxAmplitude: Float
    let averageAmplitude: Float
    
    struct TrackedPoint: Codable {
        let x: Float
        let y: Float
        let z: Float
        let timestamp: TimeInterval
    }
    
    // Convenience initializer that converts SIMD3<Float> to TrackedPoint
    init(attemptNumber: Int, timestamp: Date, userTrace: [(SIMD3<Float>, TimeInterval)], 
         headsetPosition: SIMD3<Float>?, objectPosition: SIMD3<Float>?, 
         totalTraceLength: Float, maxAmplitude: Float, averageAmplitude: Float) {
        self.attemptNumber = attemptNumber
        self.timestamp = timestamp
        self.userTrace = userTrace.map { TrackedPoint(x: $0.0.x, y: $0.0.y, z: $0.0.z, timestamp: $0.1) }
        self.headsetPosition = headsetPosition.map { TrackedPoint(x: $0.x, y: $0.y, z: $0.z, timestamp: 0) }
        self.objectPosition = objectPosition.map { TrackedPoint(x: $0.x, y: $0.y, z: $0.z, timestamp: 0) }
        self.totalTraceLength = totalTraceLength
        self.maxAmplitude = maxAmplitude
        self.averageAmplitude = averageAmplitude
    }
}

class DataManager: ObservableObject {
    @Published var totalTraceLength: Float = 0
    @Published var maxAmplitude: Float = 0
    @Published var averageAmplitude: Float = 0
    
    @Published var straight1HeadsetPosition: SIMD3<Float>? = nil
    @Published var straight2HeadsetPosition: SIMD3<Float>? = nil
    @Published var straight3HeadsetPosition: SIMD3<Float>? = nil
    @Published var straight4HeadsetPosition: SIMD3<Float>? = nil

    @Published var straight1ObjectPosition: SIMD3<Float>? = nil
    @Published var straight2ObjectPosition: SIMD3<Float>? = nil
    @Published var straight3ObjectPosition: SIMD3<Float>? = nil
    @Published var straight4ObjectPosition: SIMD3<Float>? = nil
    
    @Published var zigzagBeginnerHeadsetPosition: SIMD3<Float>? = nil
    @Published var zigzagBeginnerObjectPosition: SIMD3<Float>? = nil
    @Published var zigzagAdvancedHeadsetPosition: SIMD3<Float>? = nil
    @Published var zigzagAdvancedObjectPosition: SIMD3<Float>? = nil
    
    @Published var currentStep: Step = .straight1
    @Published var currentAttempt: Int = 1
    @Published var stepDidChange: Bool = false
    @Published var assessmentCompleted: Bool = false
    @Published var isFingerStable: Bool = false
    @Published var isFingerBeingTracked: Bool = false
    @Published var isFingerTooFar: Bool = false
    @Published var stabilityCountdown: Int = 2
    @Published var isTracing: Bool = false
    @Published var tracingStabilityCountdown: Int = 2
    @Published var isShowingCompletionCountdown: Bool = false
    @Published var isFingerTooCloseForFinish: Bool = false
    @Published var isAnimationComplete: Bool = false // When tracing, finger must move forward past maxStartingDistance to finish
    @Published var forceStartTracing: Bool = false // Force start tracing without stability wait
    @Published var forceStopTracing: Bool = false // Force stop tracing and proceed to next step
    @Published var isShowingStepComplete: Bool = false  // Show checkmark after completing a step
    @Published var stepCompleteProgress: Double = 0.0   // Progress for checkmark animation
    
    // Calibration states
    @Published var calibrationPhase: CalibrationPhase = .waitingForHead
    @Published var leftHandDetected: Bool = false
    @Published var rightHandDetected: Bool = false
    @Published var calibrationCountdown: Int = 2
    @Published var calibrationProgress: Double = 0.0  // 0.0 to 1.0 for circular progress animation
    @Published var checkmarkProgress: Double = 0.0    // 0.0 to 1.0 for checkmark drawing animation
    @Published var calibrationComplete: Bool = false
    @Published var selectedHand: HandSide? = nil
    
    enum CalibrationPhase {
        case waitingForHead          // "Please keep your head in front of the headset..."
        case waitingForOneHand       // Waiting for user to show one hand
        case holdingSteady           // "I can see your [hand], hold it ahead for 3 seconds"
        case countingDown            // Counting down from 3 to 1
        case complete                // Calibration finished, proceed to assessment
    }
    
    enum HandSide {
        case left
        case right
    }

    // Store all attempts for each step
    @Published var straight1Attempts: [TraceAttempt] = []
    @Published var straight2Attempts: [TraceAttempt] = []
    @Published var straight3Attempts: [TraceAttempt] = []
    @Published var straight4Attempts: [TraceAttempt] = []
    @Published var zigzagBeginnerAttempts: [TraceAttempt] = []
    @Published var zigzagAdvancedAttempts: [TraceAttempt] = []

    // Legacy support - current attempt traces
    @Published var straight1UserTrace: [(SIMD3<Float>, TimeInterval)] = []
    @Published var straight2UserTrace: [(SIMD3<Float>, TimeInterval)] = []
    @Published var straight3UserTrace: [(SIMD3<Float>, TimeInterval)] = []
    @Published var straight4UserTrace: [(SIMD3<Float>, TimeInterval)] = []
    @Published var zigzagBeginnerUserTrace: [(SIMD3<Float>, TimeInterval)] = []
    @Published var zigzagAdvancedUserTrace: [(SIMD3<Float>, TimeInterval)] = []
    
    func setTotalTraceLength(_ length: Float) {
        self.totalTraceLength = length
    }
    
    func setMaxAmplitude(_ amplitude: Float) {
        self.maxAmplitude = amplitude
    }
    
    func setAverageAmplitude(_ amplitude: Float) {
        self.averageAmplitude = amplitude
    }
    
    func getCompletedAttempts(for step: Step) -> Int {
        switch step {
        case .straight1: return straight1Attempts.count
        case .straight2: return straight2Attempts.count
        case .straight3: return straight3Attempts.count
        case .straight4: return straight4Attempts.count
        case .zigzagBeginner: return zigzagBeginnerAttempts.count
        case .zigzagAdvanced: return zigzagAdvancedAttempts.count
        }
    }
    
    func isStepComplete(for step: Step) -> Bool {
        return getCompletedAttempts(for: step) >= 10
    }
    
    func canMoveToNextStep() -> Bool {
        return isStepComplete(for: currentStep)
    }
    
    func saveCurrentAttempt() {
        let userTrace = getUserTrace(for: currentStep)
        print("💾 Saving attempt \(currentAttempt) for step \(currentStep)")
        print("💾 User trace has \(userTrace.count) points")
        
        let attempt = TraceAttempt(
            attemptNumber: currentAttempt,
            timestamp: Date(),
            userTrace: userTrace,
            headsetPosition: getHeadsetPosition(for: currentStep),
            objectPosition: getObjectPosition(for: currentStep),
            totalTraceLength: totalTraceLength,
            maxAmplitude: maxAmplitude,
            averageAmplitude: averageAmplitude
        )
        
        switch currentStep {
        case .straight1: 
            straight1Attempts.append(attempt)
            print("💾 Straight1 now has \(straight1Attempts.count) attempts")
        case .straight2: 
            straight2Attempts.append(attempt)
            print("💾 Straight2 now has \(straight2Attempts.count) attempts")
        case .straight3: 
            straight3Attempts.append(attempt)
            print("💾 Straight3 now has \(straight3Attempts.count) attempts")
        case .straight4: 
            straight4Attempts.append(attempt)
            print("💾 Straight4 now has \(straight4Attempts.count) attempts")
        case .zigzagBeginner: 
            zigzagBeginnerAttempts.append(attempt)
            print("💾 ZigzagBeginner now has \(zigzagBeginnerAttempts.count) attempts")
        case .zigzagAdvanced: 
            zigzagAdvancedAttempts.append(attempt)
            print("💾 ZigzagAdvanced now has \(zigzagAdvancedAttempts.count) attempts")
        }
        
        // Move to next attempt or next step
        if currentAttempt < 10 {
            currentAttempt += 1
        } else {
            currentAttempt = 1
            nextStep()
        }
    }
    
    private func getHeadsetPosition(for step: Step) -> SIMD3<Float>? {
        switch step {
        case .straight1: return straight1HeadsetPosition
        case .straight2: return straight2HeadsetPosition
        case .straight3: return straight3HeadsetPosition
        case .straight4: return straight4HeadsetPosition
        case .zigzagBeginner: return zigzagBeginnerHeadsetPosition
        case .zigzagAdvanced: return zigzagAdvancedHeadsetPosition
        }
    }
    
    private func getObjectPosition(for step: Step) -> SIMD3<Float>? {
        switch step {
        case .straight1: return straight1ObjectPosition
        case .straight2: return straight2ObjectPosition
        case .straight3: return straight3ObjectPosition
        case .straight4: return straight4ObjectPosition
        case .zigzagBeginner: return zigzagBeginnerObjectPosition
        case .zigzagAdvanced: return zigzagAdvancedObjectPosition
        }
    }
    
    func nextStep() {
        switch currentStep {
        case .straight1:
            currentStep = .straight2
        case .straight2:
            currentStep = .straight3
        case .straight3:
            currentStep = .straight4
        case .straight4:
            currentStep = .zigzagBeginner
        case .zigzagBeginner:
            currentStep = .zigzagAdvanced
        case .zigzagAdvanced:
            break
        }
        stepDidChange.toggle()
    }

    // Updated to accept and set trace with timestamp data
    func setUserTrace(_ trace: [(SIMD3<Float>, TimeInterval)], for step: Step) {
        switch step {
        case .straight1: straight1UserTrace = trace
        case .straight2: straight2UserTrace = trace
        case .straight3: straight3UserTrace = trace
        case .straight4: straight4UserTrace = trace
        case .zigzagBeginner: zigzagBeginnerUserTrace = trace
        case .zigzagAdvanced: zigzagAdvancedUserTrace = trace
        }
    }

    // Updated to return trace with timestamp data
    func getUserTrace(for step: Step) -> [(SIMD3<Float>, TimeInterval)] {
        switch step {
        case .straight1: return straight1UserTrace
        case .straight2: return straight2UserTrace
        case .straight3: return straight3UserTrace
        case .straight4: return straight4UserTrace
        case .zigzagBeginner: return zigzagBeginnerUserTrace
        case .zigzagAdvanced: return zigzagAdvancedUserTrace
        }
    }
    
    // Helper method to get just the positions without timestamps for legacy uses
    func getUserTracePositions(for step: Step) -> [SIMD3<Float>] {
        return getUserTrace(for: step).map { $0.0 }
    }
    
    // Export the user trace for the given step as a CSV string
    // CSV columns: time,x,y,z
    func exportUserTraceCSV(for step: Step) -> String {
        let trace = getUserTrace(for: step)
        // Header line
        var csvString = "time,x,y,z\n"
        for (position, time) in trace {
            // Format floats and time with fixed decimals for CSV clarity
            let line = String(format: "%.3f,%.6f,%.6f,%.6f\n", time, position.x, position.y, position.z)
            csvString.append(line)
        }
        return csvString
    }
    
    // Export all attempts for all steps as comprehensive CSV
    func exportAllAttemptsToCSV() -> String {
        var csvContent = "Step,AttemptNumber,Timestamp,TotalTraceLength,MaxAmplitude,AverageAmplitude,TracePointX,TracePointY,TracePointZ,TracePointTime\n"
        
        let allSteps: [Step] = [.straight1, .straight2, .straight3, .straight4, .zigzagBeginner, .zigzagAdvanced]
        
        for step in allSteps {
            let attempts = getAttempts(for: step)
            for attempt in attempts {
                let stepName = getStepName(step)
                let baseInfo = "\(stepName),\(attempt.attemptNumber),\(attempt.timestamp),\(attempt.totalTraceLength),\(attempt.maxAmplitude),\(attempt.averageAmplitude)"
                
                for point in attempt.userTrace {
                    csvContent += "\(baseInfo),\(point.x),\(point.y),\(point.z),\(point.timestamp)\n"
                }
            }
        }
        
        return csvContent
    }
    
    func getAttempts(for step: Step) -> [TraceAttempt] {
        switch step {
        case .straight1: return straight1Attempts
        case .straight2: return straight2Attempts
        case .straight3: return straight3Attempts
        case .straight4: return straight4Attempts
        case .zigzagBeginner: return zigzagBeginnerAttempts
        case .zigzagAdvanced: return zigzagAdvancedAttempts
        }
    }
    
    private func getStepName(_ step: Step) -> String {
        switch step {
        case .straight1: return "Straight1"
        case .straight2: return "Straight2"
        case .straight3: return "Straight3"
        case .straight4: return "Straight4"
        case .zigzagBeginner: return "ZigzagBeginner"
        case .zigzagAdvanced: return "ZigzagAdvanced"
        }
    }
    
    // Export data for a specific step
    func exportStepDataToCSV(for step: Step) -> String {
        var rows: [String] = ["task,path_type,attempt_number,point_idx,timestamp,x,y,z"]
        
        let taskName = getStepName(step)
        
        // Add guide dots first (if positions are available)
        let guideDots = getGuideDots(for: step)
        for (i, point) in guideDots.enumerated() {
            rows.append("\(taskName),guide,,\(i),,\(point.x),\(point.y),\(point.z)")
        }
        
        // Add all user attempts for this step
        let attempts = getAttempts(for: step)
        for attempt in attempts {
            for (i, point) in attempt.userTrace.enumerated() {
                rows.append("\(taskName),user,\(attempt.attemptNumber),\(i),\(point.timestamp),\(point.x),\(point.y),\(point.z)")
            }
        }
        
        return rows.joined(separator: "\n")
    }
    
    private func getGuideDots(for step: Step) -> [SIMD3<Float>] {
        guard let start = getHeadsetPosition(for: step),
              let end = getObjectPosition(for: step) else {
            return []
        }
        
        switch step {
        case .zigzagBeginner:
            return generateZigZagGuideDots(start: start, end: end, amplitude: 0.05, frequency: 2)
        case .zigzagAdvanced:
            return generateZigZagGuideDots(start: start, end: end, amplitude: 0.05, frequency: 4)
        default:
            return generateStraightLineGuideDots(start: start, end: end)
        }
    }
    
    private func generateStraightLineGuideDots(start: SIMD3<Float>, end: SIMD3<Float>) -> [SIMD3<Float>] {
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
        for i in 0...numberOfSegments {
            let t = Float(i) / Float(numberOfSegments)
            let point = start + direction * (lineLength * t)
            dots.append(point)
        }
        return dots
    }
    
    private func generateZigZagGuideDots(start: SIMD3<Float>, end: SIMD3<Float>, amplitude: Float, frequency: Int, dotSpacing: Float = 0.001, maxDots: Int = 1000) -> [SIMD3<Float>] {
        let lineVector = end - start
        let lineLength = length(lineVector)
        if lineLength == 0 {
            return [start]
        }
        let direction = normalize(lineVector)
        let numberOfSegments = min(Int(lineLength / dotSpacing), maxDots)
        
        let up: SIMD3<Float> = abs(direction.y) < 0.99 ? [0, 1, 0] : [1, 0, 0]
        let right = normalize(cross(direction, up))
        
        var dots: [SIMD3<Float>] = []
        for i in 0...numberOfSegments {
            let t = Float(i) / Float(numberOfSegments)
            let basePoint = start + direction * (lineLength * t)
            let angle = t * Float(frequency) * 2.0 * .pi
            let offset = right * sin(angle) * amplitude
            dots.append(basePoint + offset)
        }
        return dots
    }
}

