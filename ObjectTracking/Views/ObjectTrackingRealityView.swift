//  ObjectTrackingRealityView.swift
//

import RealityKit
import ARKit
import SwiftUI
import Combine
import simd

extension Notification.Name {
    static let showSummaryView = Notification.Name("showSummaryView")
}

extension ARKitSession: ObservableObject {}
extension WorldTrackingProvider: ObservableObject {}
extension HandTrackingProvider: ObservableObject {}

@MainActor
struct ObjectTrackingRealityView: View {

    @State var appState: AppState

    @StateObject private var session      = ARKitSession()
    @StateObject private var worldInfo    = WorldTrackingProvider()
    @StateObject private var handTracking = HandTrackingProvider()
    @EnvironmentObject var dataManager: DataManager

    private let root = Entity()
    @State private var objectVisualization: ObjectAnchorVisualization?
    @State private var trackedAnchors: [UUID: ObjectAnchor] = [:]
    
    @State private var buttonPositions: [UUID: CGPoint] = [:]
    @State private var screenSize: CGSize = .zero
    
    @State private var isTracing: Bool = false
    @State private var lastFingerPosition: SIMD3<Float>?
    @State private var tracingStartTime: TimeInterval = 0
    
    @State private var fingerStationary: Bool = false
    @State private var stationaryTimer: Timer?
    @State private var lastMovementTime: TimeInterval = 0
    
    private let stationaryThreshold: Float = 0.01
    private let fingerTouchThreshold: Float = 0.005
    
    @State private var sharedFingerTracker: FingerTracker?

    @State private var updateTask: Task<Void, Never>?

    @State private var traceArmed: Bool = false
    
    @State private var isTracingLocked: Bool = false
    
    // Finger stability tracking
    @State private var rightFingerPosition: SIMD3<Float>?
    @State private var rightFingerStabilityStart: TimeInterval?
    @State private var rightFingerStabilityStartPosition: SIMD3<Float>? // Position when stability timer started
    @State private var isFingerStable: Bool = false
    @State private var stableFingerPosition: SIMD3<Float>? = nil
    @State private var fixedStartingPosition: SIMD3<Float>? = nil // Fixed starting point for all attempts
    @State private var fixedEndPosition: SIMD3<Float>? // Stores the end position from attempt 1
    @State private var fixedPositionStep: Step? // Stores which step the fixed positions belong to
    @State private var previousStep: Step? = nil // Track previous step to detect step type changes
    @State private var isFingerBeingTracked: Bool = false
    @State private var isFingerTooFar: Bool = false // Finger detected but too far from headset
    @State private var stabilityCountdown: Int = 2
    @State private var lastFingerUpdateTime: TimeInterval = 0
    
    // Tracing completion stability tracking
    @State private var tracingStabilityStart: TimeInterval? = nil
    @State private var tracingStabilityCountdown: Int = 2
    @State private var lastTracingPosition: SIMD3<Float>? = nil
    @State private var tracingStabilityStartPosition: SIMD3<Float>? = nil // Position where tracing stability started
    @State private var isShowingCompletionCountdown: Bool = false
    
    // Hand detection tracking (reset periodically to detect disappearances)
    @State private var lastLeftHandUpdate: TimeInterval = 0
    @State private var lastRightHandUpdate: TimeInterval = 0
    
    private let stabilityThreshold: Float = 0.050 // 50mm (5cm) - allows comfortable natural hand movements
    private let stabilityDuration: TimeInterval = 2.0 // 2 seconds
    private let initialStillDuration: TimeInterval = 1.0 // 1 second before countdown starts
    private let maxStartingDistance: Float = 0.30 // 30cm - maximum distance from headset to start tracing

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RealityView { content in
                    try? await session.run([worldInfo, handTracking])
                    content.add(root)
                    
                    DispatchQueue.main.async {
                        screenSize = geometry.size
                    }

                    Task { @MainActor in
                        for await update in handTracking.anchorUpdates {
                            let handAnchor = update.anchor
                            guard let skel = handAnchor.handSkeleton else { continue }

                            let indexTip = skel.joint(.indexFingerTip)
                            guard indexTip.isTracked else { continue }

                            let indexWorldMatrix = handAnchor.originFromAnchorTransform * indexTip.anchorFromJointTransform
                            let indexTipPos = SIMD3<Float>(
                                indexWorldMatrix.columns.3.x,
                                indexWorldMatrix.columns.3.y,
                                indexWorldMatrix.columns.3.z
                            )
                            
                            // Skip hands that are not in front of the user (e.g., on lap, behind, far to sides)
                            guard isHandInFrontOfUser(handPosition: indexTipPos) else { continue }
                            
                            let currentTime = CACurrentMediaTime()

                            // Track both hands during calibration, specific hand after
                            if !dataManager.calibrationComplete {
                                // Update hand detection status with timestamps
                                if handAnchor.chirality == .left {
                                    lastLeftHandUpdate = currentTime
                                    dataManager.leftHandDetected = true
                                } else if handAnchor.chirality == .right {
                                    lastRightHandUpdate = currentTime
                                    dataManager.rightHandDetected = true
                                }
                                
                                // Handle calibration logic
                                await handleCalibration(handAnchor: handAnchor, indexTipPos: indexTipPos)
                            } else {
                                // Normal assessment mode - only track selected hand
                                let shouldTrack = if let selectedHand = dataManager.selectedHand {
                                    (selectedHand == .left && handAnchor.chirality == .left) ||
                                    (selectedHand == .right && handAnchor.chirality == .right)
                                } else {
                                    false
                                }
                                
                                guard shouldTrack else { continue }
                                
                                // Check for force start tracing
                                if dataManager.forceStartTracing {
                                    dataManager.forceStartTracing = false
                                    // Force start tracing without stability wait
                                    isFingerBeingTracked = true
                                    dataManager.isFingerBeingTracked = true
                                    isFingerTooFar = false
                                    dataManager.isFingerTooFar = false
                                    isFingerStable = true
                                    dataManager.isFingerStable = true
                                    stableFingerPosition = indexTipPos
                                    updateLinePositionsBasedOnFinger(indexTipPos)
                                    objectVisualization?.showVisualizations()
                                    objectVisualization?.startTracing()
                                    traceArmed = true
                                    startTracing()
                                    continue // Skip normal processing
                                }
                                
                                // Check for force stop tracing
                                if dataManager.forceStopTracing {
                                    print("⚠️ Force stop tracing button pressed")
                                    dataManager.forceStopTracing = false
                                    // Force stop tracing
                                    stopTracing()
                                    // Complete current attempt (this will save and export if needed)
                                    await completeCurrentAttempt()
                                    continue // Skip normal processing
                                }
                                
                                // Update tracking status and timestamp FIRST for immediate responsiveness
                                lastFingerUpdateTime = CACurrentMediaTime()
                                
                                // Check if finger is close enough to start tracing (only when not already tracing)
                                let isCloseEnough = isFingerCloseEnoughToStart(fingerPosition: indexTipPos)
                                
                                if !isFingerBeingTracked {
                                    isFingerBeingTracked = true
                                    dataManager.isFingerBeingTracked = true
                                }
                                
                                // Update distance status (only matters when not already tracing)
                                if !isTracing {
                                    isFingerTooFar = !isCloseEnough
                                    dataManager.isFingerTooFar = isFingerTooFar
                                }
                                
                                // Only update if finger has moved significantly (1mm threshold) to reduce processing
                                let shouldUpdate = if let lastPos = lastFingerPosition {
                                    distance(indexTipPos, lastPos) > 0.001 // 1mm threshold
                                } else {
                                    true // First time tracking
                                }
                                
                                if shouldUpdate {
                                    lastFingerPosition = indexTipPos
                                    
                                    // Only allow stability updates if finger is close enough OR already tracing
                                    if isCloseEnough || isTracing {
                                        await updateFingerStability(position: indexTipPos, isRightHand: handAnchor.chirality == .right)
                                    } else {
                                        // Finger too far - reset stability
                                        rightFingerStabilityStart = nil
                                        rightFingerStabilityStartPosition = nil
                                        isFingerStable = false
                                        dataManager.isFingerStable = false
                                        stabilityCountdown = 2
                                        dataManager.stabilityCountdown = 2
                                    }
                                    
                                    if let d = objectVisualization?.distanceFromFinger(to: indexTipPos) {
                                        objectVisualization?.updateDistance(d)
                                    }
                                    
                                    if isFingerStable {
                                        await handleFingerTracing(indexTipPosition: indexTipPos)
                                    }
                                } else {
                                    // Still update stability timing even if position hasn't changed much
                                    if isCloseEnough || isTracing {
                                        await updateFingerStability(position: indexTipPos, isRightHand: handAnchor.chirality == .right)
                                    }
                                }
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            appState.isImmersiveSpaceOpened = true
            
            // Reset fixed starting position for new assessment
            fixedStartingPosition = nil
            
            // Initialize finger tracking time to current time
            lastFingerUpdateTime = CACurrentMediaTime()
            
            // Start hand detection reset timer for calibration
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                guard !dataManager.calibrationComplete else {
                    timer.invalidate()
                    return
                }
                
                let currentTime = CACurrentMediaTime()
                let handTimeout: TimeInterval = 0.15 // 150ms timeout
                
                // Reset hand flags if not seen recently
                if currentTime - lastLeftHandUpdate > handTimeout {
                    dataManager.leftHandDetected = false
                }
                if currentTime - lastRightHandUpdate > handTimeout {
                    dataManager.rightHandDetected = false
                }
                
                // Also check calibration state transitions when no hands visible
                Task { @MainActor in
                    await self.checkCalibrationState()
                }
            }

            let offset = SIMD3<Float>(0, 0, 0)
            let deviceAnchor = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
            let virtualPoint: SIMD3<Float>
            if let deviceAnchor = deviceAnchor {
                virtualPoint = worldPosition(relativeOffset: offset, deviceTransform: deviceAnchor.originFromAnchorTransform)
            } else {
                virtualPoint = offset
            }
            
            // Create shared finger tracker
            sharedFingerTracker = FingerTracker(parentEntity: root, objectExtents: [0.1, 0.1, 0.1])
            
            let viz = ObjectAnchorVisualization(using: worldInfo, dataManager: dataManager, virtualPoint: virtualPoint, fingerTracker: sharedFingerTracker!)
            root.addChild(viz.entity)
            objectVisualization = viz
            
            // Entity starts disabled by default - nothing should show until finger stability
            
            updateTask = Task {
                while !Task.isCancelled {
                    let currentTime = CACurrentMediaTime()
                    
                    // Check if finger tracking was lost (no updates for 0.5 seconds)
                    if currentTime - lastFingerUpdateTime > 0.5 {
                        if isFingerBeingTracked {
                            isFingerBeingTracked = false
                            dataManager.isFingerBeingTracked = false
                            isFingerTooFar = false
                            dataManager.isFingerTooFar = false
                            // Reset stability when tracking is lost
                            rightFingerStabilityStart = nil
                            rightFingerStabilityStartPosition = nil
                            stabilityCountdown = 2
                            dataManager.stabilityCountdown = 2
                        }
                    }
                    
                    // Update countdown for initial stability (before tracing)
                    if isFingerBeingTracked && !isFingerStable {
                        let stabilityStart = rightFingerStabilityStart
                        if let start = stabilityStart {
                            let elapsed = currentTime - start
                            let remaining = max(1, Int(ceil(stabilityDuration - elapsed)))
                            // When elapsed >= stabilityDuration, finger should be stable
                            let finalCountdown = elapsed >= stabilityDuration ? 0 : remaining
                            if finalCountdown != stabilityCountdown {
                                stabilityCountdown = finalCountdown
                                dataManager.stabilityCountdown = finalCountdown
                            }
                        }
                    }
                    
                    // Countdown updates are now handled directly in checkTracingStability for better responsiveness
                    
                    // Only run update loop when finger is stable OR tracing OR retracting
                    // Before stability, nothing should be shown
                    if isFingerStable || isTracing {
                        let offset = SIMD3<Float>(0, -0.20, -0.6)
                        let deviceAnchor = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())
                        let virtualPoint: SIMD3<Float>
                        if let deviceAnchor = deviceAnchor {
                            virtualPoint = worldPosition(relativeOffset: offset, deviceTransform: deviceAnchor.originFromAnchorTransform)
                        } else {
                            virtualPoint = offset
                        }
                        // Update with finger-based positions (which are now fixed)
                        objectVisualization?.update(virtualPoint: virtualPoint)
                        
                        // Sync animation state
                        if let isComplete = objectVisualization?.isAnimationComplete {
                            DispatchQueue.main.async {
                                self.dataManager.isAnimationComplete = isComplete
                            }
                        }
                    }
                    // Adaptive update frequency: high during active tracking, lower when idle
                    if isTracing || isShowingCompletionCountdown || (!isFingerStable && isFingerBeingTracked) {
                        try? await Task.sleep(nanoseconds: 16_666_667) // ~60 FPS for active periods
                    } else {
                        try? await Task.sleep(nanoseconds: 33_333_333) // ~30 FPS when idle
                    }
                }
            }
        }
        .onDisappear {
            // Clean up timers
            stationaryTimer?.invalidate()
            stationaryTimer = nil
            
            updateTask?.cancel()
            updateTask = nil
            
            if let viz = objectVisualization {
                root.removeChild(viz.entity)
            }
            objectVisualization = nil
            trackedAnchors.removeAll()
            buttonPositions.removeAll()
            
            appState.didLeaveImmersiveSpace()
        }
        .onChange(of: dataManager.currentStep) { newStep in
            // Reset timer to current time so countdown starts immediately if finger is being tracked
            if isFingerBeingTracked {
                rightFingerStabilityStart = CACurrentMediaTime()
                rightFingerStabilityStartPosition = rightFingerPosition // Set current position as new start
            } else {
                rightFingerStabilityStart = nil
                rightFingerStabilityStartPosition = nil
            }
            stabilityCountdown = 2
            dataManager.stabilityCountdown = 2
            
            // Reset tracing state for new step
            traceArmed = false
            isTracingLocked = false
            isTracing = false
            dataManager.isTracing = false
        tracingStabilityStart = nil
        tracingStabilityCountdown = 2
        dataManager.tracingStabilityCountdown = 2
            lastTracingPosition = nil
            tracingStabilityStartPosition = nil
            isShowingCompletionCountdown = false
            dataManager.isShowingCompletionCountdown = false
            
            objectVisualization?.resetVisualizations()
            // Only hide visualizations if we're not going to show preview line
            if fixedStartingPosition == nil {
                objectVisualization?.hideVisualizations()
            }
            
            // Show preview line immediately for attempts 2+ (after first attempt)
            if fixedStartingPosition != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.showPreviewLine()
                }
            }
        }
        .onChange(of: dataManager.currentAttempt) { newAttempt in
            print("Attempt changed to: \(newAttempt), fixedStartingPosition exists: \(fixedStartingPosition != nil)")
            // Show preview line when starting attempt 2+ within the same step
            if newAttempt > 1 && fixedStartingPosition != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("Showing preview line from attempt change")
                    self.showPreviewLine()
                }
            }
        }
    }
    
    private func getLocalTargetOffset(for step: Step) -> SIMD3<Float> {
        // Base offset is (0, -0.20, -0.6) which is "Forward and Down"
        // We modify this base offset to define the target for each step
        switch step {
        case .straight1:
            return SIMD3<Float>(0, -0.20, -0.6)       // Straight forward/down
        case .straight2:
            return SIMD3<Float>(0.3, -0.20, -0.6)     // Right
        case .straight3:
            return SIMD3<Float>(0, 0.10, -0.6)        // Up
        case .straight4:
            return SIMD3<Float>(-0.3, -0.20, -0.6)    // Left
        case .zigzagBeginner, .zigzagAdvanced:
            return SIMD3<Float>(0, -0.20, -0.6)       // Default for zigzag
        }
    }
    
    private func showPreviewLine() {
        guard let fixedStart = fixedStartingPosition,
              let deviceAnchor = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            print("Cannot show preview line - fixedStart: \(fixedStartingPosition != nil), deviceAnchor: \(worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) != nil)")
            return
        }
        
        print("Showing preview line for step: \(dataManager.currentStep)")
        
        // Calculate the same line positions as in updateLinePositionsBasedOnFinger
        let localTargetOffset = getLocalTargetOffset(for: dataManager.currentStep)
        let worldTargetPos = worldPosition(relativeOffset: localTargetOffset, deviceTransform: deviceAnchor.originFromAnchorTransform)
        
        // Unused variables removed
        
        let newEndPos = worldTargetPos
        
        // Update data manager with preview line positions
        switch dataManager.currentStep {
        case .straight1:
            dataManager.straight1HeadsetPosition = fixedStart
            dataManager.straight1ObjectPosition = newEndPos
        case .straight2:
            dataManager.straight2HeadsetPosition = fixedStart
            dataManager.straight2ObjectPosition = newEndPos
        case .straight3:
            dataManager.straight3HeadsetPosition = fixedStart
            dataManager.straight3ObjectPosition = newEndPos
        case .straight4:
            dataManager.straight4HeadsetPosition = fixedStart
            dataManager.straight4ObjectPosition = newEndPos
        case .zigzagBeginner:
            dataManager.zigzagBeginnerHeadsetPosition = fixedStart
            dataManager.zigzagBeginnerObjectPosition = newEndPos
        case .zigzagAdvanced:
            dataManager.zigzagAdvancedHeadsetPosition = fixedStart
            dataManager.zigzagAdvancedObjectPosition = newEndPos
        }
        
        // Show the preview line and dots immediately
        objectVisualization?.showVisualizations()
    }
    
    private func updateButtonPosition(for anchor: ObjectAnchor, id: UUID) async {
        guard let devicePose = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return
        }
        
        let objectWorldPos = SIMD3<Float>(
            anchor.originFromAnchorTransform.columns.3.x,
            anchor.originFromAnchorTransform.columns.3.y,
            anchor.originFromAnchorTransform.columns.3.z
        )
        
        let deviceWorldPos = SIMD3<Float>(
            devicePose.originFromAnchorTransform.columns.3.x,
            devicePose.originFromAnchorTransform.columns.3.y,
            devicePose.originFromAnchorTransform.columns.3.z
        )
        
        if let screenPos = projectWorldToScreen(
            worldPosition: objectWorldPos,
            devicePosition: deviceWorldPos,
            screenSize: screenSize
        ) {
            let rightOffset: CGFloat = 200
            let buttonPosition = CGPoint(
                x: min(screenPos.x + rightOffset, screenSize.width - 100),
                y: screenPos.y
            )
            
            DispatchQueue.main.async {
                // Only update if position has changed significantly to reduce UI updates
                if let existingPos = buttonPositions[id] {
                    let deltaX = abs(buttonPosition.x - existingPos.x)
                    let deltaY = abs(buttonPosition.y - existingPos.y)
                    if deltaX > 1.0 || deltaY > 1.0 {
                        buttonPositions[id] = buttonPosition
                    }
                } else {
                    buttonPositions[id] = buttonPosition
                }
            }
        }
    }
    
    private func projectWorldToScreen(
        worldPosition: SIMD3<Float>,
        devicePosition: SIMD3<Float>,
        screenSize: CGSize
    ) -> CGPoint? {
        guard screenSize.width > 0 && screenSize.height > 0 else { return nil }
        
        let objectVector = worldPosition - devicePosition
        
        if objectVector.z > -0.01 { return nil }
        
        let fov: Float = 60.0 * .pi / 180.0
        let aspectRatio = Float(screenSize.width / screenSize.height)
        
        let depth = abs(objectVector.z)
        let x = objectVector.x / depth
        let y = objectVector.y / depth
        
        let tanHalfFov = tan(fov / 2.0)
        let normalizedX = x / tanHalfFov / aspectRatio
        let normalizedY = y / tanHalfFov
        
        if abs(normalizedX) > 1.0 || abs(normalizedY) > 1.0 {
            return nil
        }
        
        let screenX = (normalizedX + 1.0) * 0.5 * Float(screenSize.width)
        let screenY = (1.0 - normalizedY) * 0.5 * Float(screenSize.height)
        
        return CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))
    }
    
    private func handleFingerTracing(indexTipPosition: SIMD3<Float>) async {
        // Start tracing immediately when finger is stable (already at starting position)
        if !isTracing && !isTracingLocked {
            startTracing()
        }
        
        // Continue tracing and check for completion via stability
        if isTracing && !isTracingLocked {
            // Update finger trace
            objectVisualization?.updateFingerTrace(fingerWorldPos: indexTipPosition)
            
            // Check for stability during tracing to complete attempt
            await checkTracingStability(position: indexTipPosition)
        }
        
        lastFingerPosition = indexTipPosition
    }
    
    private func startTracing() {
        isTracing = true
        dataManager.isTracing = true
        isFingerTooFar = false  // Reset distance check once tracing starts
        dataManager.isFingerTooFar = false
        tracingStartTime = CACurrentMediaTime()
        lastMovementTime = CACurrentMediaTime()
        fingerStationary = false
        stationaryTimer?.invalidate()
        
    // Reset tracing stability tracking
    tracingStabilityStart = nil
    tracingStabilityCountdown = 2
    dataManager.tracingStabilityCountdown = 2
    lastTracingPosition = nil
        tracingStabilityStartPosition = nil
        isShowingCompletionCountdown = false
        dataManager.isShowingCompletionCountdown = false
        
        objectVisualization?.startTracing()
        
        print("Started finger tracing")
    }
    
    private func stopTracing() {
        isTracing = false
        dataManager.isTracing = false
        fingerStationary = false
        stationaryTimer?.invalidate()
        
    // Reset tracing stability tracking
    tracingStabilityStart = nil
    tracingStabilityCountdown = 2
    dataManager.tracingStabilityCountdown = 2
    lastTracingPosition = nil
        tracingStabilityStartPosition = nil
        isShowingCompletionCountdown = false
        dataManager.isShowingCompletionCountdown = false
        
        objectVisualization?.stopTracing()
        
        let tracingDuration = CACurrentMediaTime() - tracingStartTime
        print("Stopped finger tracing after \(String(format: "%.2f", tracingDuration)) seconds")
    dataManager.isFingerTooCloseForFinish = false
    }
    
    private func resetForNextAttempt() {
        // Reset tracing state
        traceArmed = false
        isTracingLocked = false
        isTracing = false
        dataManager.isTracing = false
        
    // Reset tracing stability tracking
    tracingStabilityStart = nil
    tracingStabilityCountdown = 2
    dataManager.tracingStabilityCountdown = 2
    lastTracingPosition = nil
        tracingStabilityStartPosition = nil
        isShowingCompletionCountdown = false
        dataManager.isShowingCompletionCountdown = false
    dataManager.isFingerTooCloseForFinish = false
        
        // Reset finger stability for next attempt (they need to stabilize again)
        isFingerStable = false
        stableFingerPosition = nil
        dataManager.isFingerStable = false
        // Reset timer to current time so countdown starts immediately if finger is being tracked
        if isFingerBeingTracked {
            rightFingerStabilityStart = CACurrentMediaTime()
            rightFingerStabilityStartPosition = rightFingerPosition // Set current position as new start
        } else {
            rightFingerStabilityStart = nil
            rightFingerStabilityStartPosition = nil
        }
    stabilityCountdown = 2
    dataManager.stabilityCountdown = 2
        
        // Clear trace and manage visualizations
        objectVisualization?.clearTrace()
        // Only hide if we won't show preview line
        if fixedStartingPosition == nil {
            objectVisualization?.hideVisualizations()
        }
        
        // Show preview line for next attempt if we have a fixed starting position
        if fixedStartingPosition != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showPreviewLine()
            }
        }
    }
    
    private func completeCurrentAttempt() async {
        // Calculate metrics for current attempt
        var totalTraceLength: Float = 0
        var maxAmplitude: Float = 0
        var averageAmplitude: Float = 0
        
        if let viz = objectVisualization {
            totalTraceLength = viz.getTraceLength()
            
            // Calculate amplitude metrics (distance from ideal path)
            let tracePoints = viz.getTracePoints()
            if !tracePoints.isEmpty {
                // Get distances to ideal path for amplitude calculation
                let distances = tracePoints.compactMap { point in
                    viz.distanceFromFinger(to: point)
                }
                
                if !distances.isEmpty {
                    maxAmplitude = distances.max() ?? 0
                    averageAmplitude = distances.reduce(0, +) / Float(distances.count)
                }
            }
        }
        
        // Update dataManager with current metrics
        dataManager.setTotalTraceLength(totalTraceLength)
        dataManager.setMaxAmplitude(maxAmplitude)
        dataManager.setAverageAmplitude(averageAmplitude)
        
        // Check if this is the 10th attempt BEFORE saving (which changes the step)
        let currentStep = dataManager.currentStep
        let isCompletingStep = dataManager.currentAttempt == 10
        let isLastStep = currentStep == .zigzagAdvanced
        
        print("🎯 Completing attempt \(dataManager.currentAttempt) for step \(currentStep)")
        print("🎯 isCompletingStep: \(isCompletingStep), isLastStep: \(isLastStep)")
        print("🎯 Total attempts before save: \(dataManager.getAttempts(for: currentStep).count)")
        
        // Save the current attempt (this will increment attempt counter or move to next step)
        dataManager.saveCurrentAttempt()
        
        print("🎯 Total attempts after save: \(dataManager.getAttempts(for: currentStep).count)")
        print("🎯 After save - now at attempt \(dataManager.currentAttempt) for step \(dataManager.currentStep)")
        
        // If we just completed all 10 attempts for a step
        if isCompletingStep {
            print("✅ Step completed! Exporting data for: \(currentStep)")
            print("✅ About to call exportStepData(for: \(currentStep))")
            
            // Export data for this completed step (for ALL steps including last)
            exportStepData(for: currentStep)
            
            if isLastStep {
                // Last step completed - show Thank You
                dataManager.assessmentCompleted = true
            } else {
                // Show checkmark animation for completed step
                dataManager.isShowingStepComplete = true
                
                // Animate checkmark drawing over 0.8 seconds
                let checkmarkDuration = 0.8
                let checkmarkUpdateInterval = 0.016  // ~60 FPS
                let checkmarkSteps = Int(checkmarkDuration / checkmarkUpdateInterval)
                
                for step in 0...checkmarkSteps {
                    self.dataManager.stepCompleteProgress = Double(step) / Double(checkmarkSteps)
                    try? await Task.sleep(nanoseconds: UInt64(checkmarkUpdateInterval * 1_000_000_000))
                }
                
                // Wait for additional delay, then move to next step
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                self.dataManager.isShowingStepComplete = false
                self.dataManager.stepCompleteProgress = 0.0
                self.resetForNextAttempt()
            }
        } else {
            // Not completing a step, just reset for next attempt after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.resetForNextAttempt()
            }
        }
    }
    
    private func exportStepData(for step: Step) {
        print("📊 Exporting data for step: \(step)")
        print("📊 Number of attempts for this step: \(dataManager.getAttempts(for: step).count)")
        
        let csvData = dataManager.exportStepDataToCSV(for: step)
        print("📊 CSV data length: \(csvData.count) characters")
        
        let stepName = getStepNameForFile(step)
        
        // Create timestamp for unique filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let fileName = "\(stepName)_Data_\(timestamp).csv"
        
        // Get documents directory
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Failed to get documents directory")
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        print("📊 Attempting to write to: \(fileURL.path)")
        print("📊 File name: \(fileName)")
        
        do {
            try csvData.write(to: fileURL, atomically: true, encoding: .utf8)
            print("✅ Successfully exported data for \(stepName) to: \(fileURL.path)")
            print("✅ File size: \(csvData.count) bytes")
        } catch {
            print("❌ Failed to export data for \(stepName): \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
    }
    
    private func getStepNameForFile(_ step: Step) -> String {
        switch step {
        case .straight1: return "Straight1"
        case .straight2: return "Straight2"
        case .straight3: return "Straight3"
        case .straight4: return "Straight4"
        case .zigzagBeginner: return "ZigzagBeginner"
        case .zigzagAdvanced: return "ZigzagAdvanced"
        }
    }
    
    private func clearTrace() {
        objectVisualization?.clearTrace()
        print("Cleared all finger traces")
    }
    
    private func worldPosition(relativeOffset: SIMD3<Float>, deviceTransform: simd_float4x4) -> SIMD3<Float> {
        let world = deviceTransform * SIMD4<Float>(relativeOffset, 1)
        return SIMD3<Float>(world.x, world.y, world.z)
    }
    
    private func checkTracingStability(position: SIMD3<Float>) async {
        // Block completion if animation is not yet complete
        if !dataManager.isAnimationComplete {
            return
        }
        
        let currentTime = CACurrentMediaTime()
        
        // Check if finger moved significantly from ORIGINAL tracing stability start position
        if let stabilityStartPos = tracingStabilityStartPosition {
            let distance = simd_distance(position, stabilityStartPos)
            if distance > stabilityThreshold {
                // Movement detected during tracing, reset everything IMMEDIATELY
                tracingStabilityStart = currentTime
                tracingStabilityStartPosition = position // Set new stability start position
                tracingStabilityCountdown = 2
                dataManager.tracingStabilityCountdown = 2
                
                // Immediate UI state change when movement detected
                if isShowingCompletionCountdown {
                    isShowingCompletionCountdown = false
                    dataManager.isShowingCompletionCountdown = false
                    print("Movement detected - returning to attempt counter")
                }
            } else {
                // Finger is stable, check which phase we're in
                if let stabilityStart = tracingStabilityStart {
                    let elapsed = currentTime - stabilityStart
                    
                    if elapsed >= initialStillDuration && !isShowingCompletionCountdown {
                        // Before starting final countdown, ensure finger is moved FORWARD past maxStartingDistance
                        if let deviceAnchor = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
                            let devicePos = SIMD3<Float>(
                                deviceAnchor.originFromAnchorTransform.columns.3.x,
                                deviceAnchor.originFromAnchorTransform.columns.3.y,
                                deviceAnchor.originFromAnchorTransform.columns.3.z
                            )
                            let distToDevice = simd_distance(position, devicePos)
                            if distToDevice > maxStartingDistance {
                                // Finger is forward enough — start Phase 2
                                dataManager.isFingerTooCloseForFinish = false
                                isShowingCompletionCountdown = true
                                dataManager.isShowingCompletionCountdown = true
                                tracingStabilityStart = currentTime // Reset timer for final countdown
                                tracingStabilityCountdown = Int(ceil(stabilityDuration))
                                dataManager.tracingStabilityCountdown = tracingStabilityCountdown
                                print("Finger forward enough — starting completion countdown")
                            } else {
                                // Finger still too close — instruct user to move it forward. Do NOT start Phase 2.
                                dataManager.isFingerTooCloseForFinish = true
                                print("Finger too close to finish — ask user to move it forward")
                            }
                        }
                    } else if isShowingCompletionCountdown {
                        // Update countdown in real-time during Phase 2
                        let remaining = max(1, Int(ceil(stabilityDuration - elapsed)))
                        let finalCountdown = elapsed >= stabilityDuration ? 0 : remaining
                        if finalCountdown != tracingStabilityCountdown {
                            tracingStabilityCountdown = finalCountdown
                            dataManager.tracingStabilityCountdown = finalCountdown
                        }
                        
                        if elapsed >= stabilityDuration {
                            // Phase 2 complete - finish attempt
                            stopTracing()
                            
                            // Capture current step before completion (which might change it)
                            let stepBeforeCompletion = dataManager.currentStep
                            
                            await completeCurrentAttempt()
                            
                            // Only lock tracing if we haven't moved to a new step
                            // (If step changed, everything was reset and should be unlocked)
                            if dataManager.currentStep == stepBeforeCompletion {
                                isTracingLocked = true
                            }
                        }
                    }
                }
            }
        } else {
            // First tracing position, start Phase 1 timer
            tracingStabilityStart = currentTime
            tracingStabilityStartPosition = position // Store the initial position
            tracingStabilityCountdown = 2
            dataManager.tracingStabilityCountdown = 2
            isShowingCompletionCountdown = false
            dataManager.isShowingCompletionCountdown = false
        }
        
        lastTracingPosition = position
    }
    
    private func updateLinePositionsBasedOnFinger(_ fingerPos: SIMD3<Float>) {
        guard let deviceAnchor = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return
        }
        
        // Robust Reset: Ensure fixed positions match the current step
        if fixedPositionStep != dataManager.currentStep {
            fixedStartingPosition = nil
            fixedEndPosition = nil
            fixedPositionStep = dataManager.currentStep
            print("Force reset fixed positions due to step mismatch (New Step: \(dataManager.currentStep))")
        }
        
        // Use fixed starting position for all attempts after first one
        let startingPos: SIMD3<Float>
        if let fixedStart = fixedStartingPosition {
            startingPos = fixedStart
        } else {
            // First attempt: use finger position and store it as fixed starting position
            startingPos = fingerPos
            fixedStartingPosition = fingerPos
            print("Set fixed starting position: \(fingerPos) for step: \(dataManager.currentStep)")
        }
        
        // Calculate new end position
        let newEndPos: SIMD3<Float>
        
        if let fixedEnd = fixedEndPosition {
            // Use fixed end position for attempts 2-10
            newEndPos = fixedEnd
            // print("Using existing fixed end position: \(fixedEnd)")
        } else {
            // Attempt 1: Calculate end position based on headset
            
            // 1. Get the Local Target Offset for this step (e.g., Right, Up, etc.)
            let localTargetOffset = getLocalTargetOffset(for: dataManager.currentStep)
            
            // 2. Transform this Local Target to World Space using the current headset transform
            // This ensures the target is relative to where the user is looking NOW
            let worldTargetPos = worldPosition(relativeOffset: localTargetOffset, deviceTransform: deviceAnchor.originFromAnchorTransform)
            
            // 3. Calculate direction from the Starting Position (Finger) to this World Target
            let directionToTarget = normalize(worldTargetPos - startingPos)
            
            // 4. Calculate length (keep consistent with original logic or use distance to target)
            // Original logic used distance from headset to object. Let's use distance from start to target.
            let traceLength = simd_distance(startingPos, worldTargetPos)
            
            // 5. Calculate new end position
            // We can just use worldTargetPos directly, or project it if we want a specific length.
            // Let's use the calculated world target directly as it respects the "relative to headset" logic best.
            newEndPos = worldTargetPos
            
            // Store as fixed end position
            fixedEndPosition = newEndPos
            print("Set fixed end position: \(newEndPos) for step: \(dataManager.currentStep)")
        }
        
        // Update data manager with new positions (always use fixed starting position)
        switch dataManager.currentStep {
        case .straight1:
            dataManager.straight1HeadsetPosition = startingPos
            dataManager.straight1ObjectPosition = newEndPos
        case .straight2:
            dataManager.straight2HeadsetPosition = startingPos
            dataManager.straight2ObjectPosition = newEndPos
        case .straight3:
            dataManager.straight3HeadsetPosition = startingPos
            dataManager.straight3ObjectPosition = newEndPos
        case .straight4:
            dataManager.straight4HeadsetPosition = startingPos
            dataManager.straight4ObjectPosition = newEndPos
        case .zigzagBeginner:
            dataManager.zigzagBeginnerHeadsetPosition = startingPos
            dataManager.zigzagBeginnerObjectPosition = newEndPos
        case .zigzagAdvanced:
            dataManager.zigzagAdvancedHeadsetPosition = startingPos
            dataManager.zigzagAdvancedObjectPosition = newEndPos
        }
    }
    
    private func updateFingerStability(position: SIMD3<Float>, isRightHand: Bool) async {
        let currentTime = CACurrentMediaTime()
        
        // Track finger stability for the selected hand (left or right after calibration)
        // Check if finger moved significantly from the ORIGINAL stability start position
        if let stabilityStartPos = rightFingerStabilityStartPosition {
            let distance = simd_distance(position, stabilityStartPos)
                if distance > stabilityThreshold {
                // Movement detected from original position, reset stability timer and countdown IMMEDIATELY
                rightFingerStabilityStart = currentTime
                rightFingerStabilityStartPosition = position // Set new stability start position
                if stabilityCountdown != 2 {
                    stabilityCountdown = 2
                    dataManager.stabilityCountdown = 2
                }
            } else {
                // Check if we've been stable long enough
                if let stabilityStart = rightFingerStabilityStart,
                   currentTime - stabilityStart >= stabilityDuration {
                    // Finger is stable
                    updateOverallStability()
                }
            }
        } else {
            // First position, start stability timer and set countdown
            rightFingerStabilityStart = currentTime
            rightFingerStabilityStartPosition = position // Store the initial position
            if stabilityCountdown != 2 {
                stabilityCountdown = 2
                dataManager.stabilityCountdown = 2
            }
        }
        rightFingerPosition = position
    }
    
    private func updateOverallStability() {
        let currentTime = CACurrentMediaTime()
        
        // Check if right hand is stable
        let rightStable = rightFingerStabilityStart != nil && 
                         currentTime - rightFingerStabilityStart! >= stabilityDuration
        
        let newStabilityState = rightStable
        
        // Use right finger position if stable
        var fingerPosToUse: SIMD3<Float>?
        if rightStable && rightFingerPosition != nil {
            fingerPosToUse = rightFingerPosition
        }
        
        if newStabilityState != isFingerStable {
            isFingerStable = newStabilityState
            dataManager.isFingerStable = newStabilityState
            
            if isFingerStable, let fingerPos = fingerPosToUse {
                // Store the stable finger position for line calculations
                stableFingerPosition = fingerPos
                
                // Calculate new line endpoints based on finger position
                updateLinePositionsBasedOnFinger(fingerPos)
                
                // Update visualization visibility and start tracing immediately
                objectVisualization?.showVisualizations()
                // Start tracing immediately since finger is at the start
                objectVisualization?.startTracing()
                
                // Set tracing state
                traceArmed = true
                startTracing()
            } else {
                stableFingerPosition = nil
                // Only hide visualizations if we're not showing a preview line
                if fixedStartingPosition == nil {
                    objectVisualization?.hideVisualizations()
                }
            }
        }
    }
    
    // MARK: - Hand Detection Area Filter
    
    private func isHandInFrontOfUser(handPosition: SIMD3<Float>) -> Bool {
        // Get the current device (headset) position and orientation
        guard let deviceAnchor = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return false
        }
        
        let deviceTransform = deviceAnchor.originFromAnchorTransform
        let devicePosition = SIMD3<Float>(
            deviceTransform.columns.3.x,
            deviceTransform.columns.3.y,
            deviceTransform.columns.3.z
        )
        
        // Get the forward direction of the headset (negative Z in device space)
        let deviceForward = SIMD3<Float>(
            -deviceTransform.columns.2.x,
            -deviceTransform.columns.2.y,
            -deviceTransform.columns.2.z
        )
        
        // Get the up direction of the headset (positive Y in device space)
        let deviceUp = SIMD3<Float>(
            deviceTransform.columns.1.x,
            deviceTransform.columns.1.y,
            deviceTransform.columns.1.z
        )
        
        // Calculate vector from device to hand
        let toHand = handPosition - devicePosition
        let toHandNormalized = normalize(toHand)
        
        // Calculate the vertical angle (pitch) relative to the forward direction
        // Project hand direction onto the vertical plane defined by forward and up vectors
        let verticalComponent = dot(toHandNormalized, deviceUp)
        let pitchRadians = asin(verticalComponent)
        let pitchDegrees = pitchRadians * 180.0 / Float.pi
        
        // Check if hand is below the limit (negative pitch = down)
        let maxDownAngle: Float = -30.0  // 30 degrees down
        if pitchDegrees < maxDownAngle {
            return false  // Hand is too far below
        }
        
        // For up, left, and right: no limit (allow any angle above horizontal and to sides)
        // Just check that hand is in front (positive dot product with forward direction)
        let forwardComponent = dot(toHandNormalized, deviceForward)
        
        // Hand must be at least somewhat in front (not behind)
        return forwardComponent > 0.0
    }
    
    private func isFingerCloseEnoughToStart(fingerPosition: SIMD3<Float>) -> Bool {
        // Check if we are currently tracing
        if isTracing {
            return false
        }
        
        // Check if finger is within 30cm of headset to start tracing
        guard let deviceAnchor = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return false
        }
        
        let deviceTransform = deviceAnchor.originFromAnchorTransform
        let devicePosition = SIMD3<Float>(
            deviceTransform.columns.3.x,
            deviceTransform.columns.3.y,
            deviceTransform.columns.3.z
        )
        
        let distance = simd_distance(fingerPosition, devicePosition)
        return distance <= maxStartingDistance
    }
    
    // MARK: - Calibration
    
    @State private var calibrationStableStart: TimeInterval? = nil
    @State private var lastCalibrationHandSide: DataManager.HandSide? = nil
    @State private var calibrationCountdownTask: Task<Void, Never>? = nil
    
    // Periodic check for calibration state transitions (called even when no hands detected)
    private func checkCalibrationState() async {
        let bothHandsVisible = dataManager.leftHandDetected && dataManager.rightHandDetected
        let oneHandVisible = dataManager.leftHandDetected != dataManager.rightHandDetected
        let noHandsVisible = !dataManager.leftHandDetected && !dataManager.rightHandDetected
        
        switch dataManager.calibrationPhase {
        case .holdingSteady:
            let correctHandVisible = if let selectedHand = dataManager.selectedHand {
                (selectedHand == .left && dataManager.leftHandDetected && !dataManager.rightHandDetected) ||
                (selectedHand == .right && dataManager.rightHandDetected && !dataManager.leftHandDetected)
            } else {
                false
            }
            
            if bothHandsVisible || !correctHandVisible {
                // User showed both hands or removed the hand - go back to waiting
                calibrationStableStart = nil
                calibrationCountdownTask?.cancel()
                calibrationCountdownTask = nil
                
                DispatchQueue.main.async {
                    self.dataManager.calibrationPhase = .waitingForOneHand
                    self.dataManager.selectedHand = nil
                    self.lastCalibrationHandSide = nil
                }
            }
            
        case .countingDown:
            let correctHandVisible = if let selectedHand = dataManager.selectedHand {
                (selectedHand == .left && dataManager.leftHandDetected && !dataManager.rightHandDetected) ||
                (selectedHand == .right && dataManager.rightHandDetected && !dataManager.leftHandDetected)
            } else {
                false
            }
            
            if bothHandsVisible || !correctHandVisible {
                // User messed up during countdown - cancel and restart
                calibrationStableStart = nil
                calibrationCountdownTask?.cancel()
                calibrationCountdownTask = nil
                
                DispatchQueue.main.async {
                    self.dataManager.calibrationPhase = .waitingForOneHand
                    self.dataManager.selectedHand = nil
                    self.dataManager.calibrationCountdown = 5
                    self.lastCalibrationHandSide = nil
                }
            }
            
        default:
            break
        }
    }
    
    private func handleCalibration(handAnchor: HandAnchor, indexTipPos: SIMD3<Float>) async {
        let currentTime = CACurrentMediaTime()
        
        // Reset hand detection flags periodically to detect when hands disappear
        // This runs every frame, so we can detect disappearances quickly
        
        switch dataManager.calibrationPhase {
        case .waitingForHead:
            // User just entered immersive space, transition to waiting for hand
            DispatchQueue.main.async {
                self.dataManager.calibrationPhase = .waitingForOneHand
            }
            
        case .waitingForOneHand:
            // Check how many hands are visible
            let bothHandsVisible = dataManager.leftHandDetected && dataManager.rightHandDetected
            let oneHandVisible = dataManager.leftHandDetected != dataManager.rightHandDetected
            let noHandsVisible = !dataManager.leftHandDetected && !dataManager.rightHandDetected
            
            if noHandsVisible {
                // No hands detected - stay in waiting phase, reset any state
                calibrationStableStart = nil
                calibrationCountdownTask?.cancel()
                calibrationCountdownTask = nil
                lastCalibrationHandSide = nil
                
                DispatchQueue.main.async {
                    self.dataManager.selectedHand = nil
                }
            } else if bothHandsVisible {
                // Reset calibration if both hands shown
                calibrationStableStart = nil
                calibrationCountdownTask?.cancel()
                calibrationCountdownTask = nil
                lastCalibrationHandSide = nil
            } else if oneHandVisible {
                // Exactly one hand visible - proceed to holding steady
                let detectedHand: DataManager.HandSide = dataManager.leftHandDetected ? .left : .right
                
                DispatchQueue.main.async {
                    self.dataManager.selectedHand = detectedHand
                    self.dataManager.calibrationPhase = .holdingSteady
                    self.calibrationStableStart = currentTime
                    self.lastCalibrationHandSide = detectedHand
                }
            }
            
        case .holdingSteady:
            // User needs to hold one hand steady for 3 seconds
            let bothHandsVisible = dataManager.leftHandDetected && dataManager.rightHandDetected
            let correctHandVisible = if let selectedHand = dataManager.selectedHand {
                (selectedHand == .left && dataManager.leftHandDetected && !dataManager.rightHandDetected) ||
                (selectedHand == .right && dataManager.rightHandDetected && !dataManager.leftHandDetected)
            } else {
                false
            }
            
            if bothHandsVisible || !correctHandVisible {
                // User showed both hands or removed the hand - go back to waiting
                calibrationStableStart = nil
                calibrationCountdownTask?.cancel()
                calibrationCountdownTask = nil
                
                DispatchQueue.main.async {
                    self.dataManager.calibrationPhase = .waitingForOneHand
                    self.dataManager.selectedHand = nil
                    self.lastCalibrationHandSide = nil
                }
            } else if let stableStart = calibrationStableStart {
                let elapsed = currentTime - stableStart
                
                if elapsed >= 1.0 {
                    // 1 second holding steady complete, start countdown animation
                    // Cancel any existing countdown task
                    calibrationCountdownTask?.cancel()
                    
                    DispatchQueue.main.async {
                        self.dataManager.calibrationPhase = .countingDown
                        self.dataManager.calibrationProgress = 0.0
                        
                        // Start smooth progress animation over 2 seconds
                        self.calibrationCountdownTask = Task { @MainActor in
                            let totalDuration = 2.0  // 2 seconds
                            let updateInterval = 0.016  // ~60 FPS
                            let steps = Int(totalDuration / updateInterval)
                            
                            for step in 0...steps {
                                // Check if task was cancelled
                                if Task.isCancelled {
                                    return
                                }
                                
                                // Update progress from 0.0 to 1.0
                                self.dataManager.calibrationProgress = Double(step) / Double(steps)
                                
                                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
                                
                                // Check again after sleep
                                if Task.isCancelled {
                                    return
                                }
                            }
                            
                            // Show "Calibration complete!" with checkmark animation
                            if !Task.isCancelled {
                                self.dataManager.calibrationProgress = 1.0
                                self.dataManager.calibrationPhase = .complete
                                self.dataManager.checkmarkProgress = 0.0
                                
                                // Wait for circle bounce animation (0.5s)
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                
                                // Animate checkmark drawing over 0.8 seconds
                                let checkmarkDuration = 0.8
                                let checkmarkUpdateInterval = 0.016  // ~60 FPS
                                let checkmarkSteps = Int(checkmarkDuration / checkmarkUpdateInterval)
                                
                                for step in 0...checkmarkSteps {
                                    if Task.isCancelled {
                                        return
                                    }
                                    
                                    self.dataManager.checkmarkProgress = Double(step) / Double(checkmarkSteps)
                                    try? await Task.sleep(nanoseconds: UInt64(checkmarkUpdateInterval * 1_000_000_000))
                                    
                                    if Task.isCancelled {
                                        return
                                    }
                                }
                                
                                // Hold completed state for 0.8 seconds
                                try? await Task.sleep(nanoseconds: 800_000_000)
                            }
                            
                            // Now proceed to assessment (only if not cancelled)
                            if !Task.isCancelled {
                                self.dataManager.calibrationComplete = true
                                self.calibrationCountdownTask = nil
                            }
                        }
                    }
                }
            }
            
        case .countingDown:
            // Check if user removed hand or showed both hands during countdown
            let bothHandsVisible = dataManager.leftHandDetected && dataManager.rightHandDetected
            let correctHandVisible = if let selectedHand = dataManager.selectedHand {
                (selectedHand == .left && dataManager.leftHandDetected && !dataManager.rightHandDetected) ||
                (selectedHand == .right && dataManager.rightHandDetected && !dataManager.leftHandDetected)
            } else {
                false
            }
            
            if bothHandsVisible || !correctHandVisible {
                // User messed up during countdown - cancel countdown task and restart
                calibrationStableStart = nil
                calibrationCountdownTask?.cancel()
                calibrationCountdownTask = nil
                
                DispatchQueue.main.async {
                    self.dataManager.calibrationPhase = .waitingForOneHand
                    self.dataManager.selectedHand = nil
                    self.dataManager.calibrationCountdown = 5
                    self.lastCalibrationHandSide = nil
                }
            }
            // Otherwise countdown task handles the progression
            
        case .complete:
            // Calibration done, normal hand tracking takes over
            break
        }
    }
}


