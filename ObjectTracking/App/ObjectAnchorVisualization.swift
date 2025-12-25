// ObjectAnchorVisualization.swift
// I3D-stroke-rehab
//
// See the LICENSE.txt file for this sample's licensing information.
//
// Abstract:
// Main visualization coordinator for object anchors with instruction text,
// a larger, more rounded “window” pane behind it, and component management,
// refactored to use a virtual point instead of an object anchor.

import ARKit
import RealityKit
import SwiftUI
import simd

@MainActor
class ObjectAnchorVisualization {
    
    private let textHeight: Float = 0.015
    private var distanceObject: Double = 0.0
    private var lastTextUpdateTime: TimeInterval = 0.0
    
    private let headsetYOffset: Float = -0.125
    private let headsetForwardOffset: Float = 0.3

    private let worldInfo: WorldTrackingProvider
    private let dataManager: DataManager
    let entity: Entity
    
    private let straightLineRenderer1: StraightLineRenderer
    private let straightLineRenderer2: StraightLineRenderer
    private let straightLineRenderer3: StraightLineRenderer
    private let straightLineRenderer4: StraightLineRenderer
    private let zigZagLineRendererBeginner: ZigZagLineRenderer
    private let zigZagLineRendererAdvanced: ZigZagLineRenderer
    private let fingerTracker: FingerTracker
    private let distanceCalculator: DistanceCalculator
    
    private var instructionText: ModelEntity?
    private var textScale: SIMD3<Float> = [1, 1, 1]
    
    // Instruction attachments for guiding the user
    private var startInstructionEntity: Entity?
    private var endInstructionEntity: Entity?
    private var isTracing: Bool = false
    
    var virtualPoint: SIMD3<Float>
    
    // Animation state
    private var animationStartTime: TimeInterval?
    private var currentAnimationStep: Step?
    
    // Animation state
    public private(set) var isAnimationComplete: Bool = false
    
    // Cache for last valid positions to prevent jumping
    private var lastValidHeadsetPos: SIMD3<Float>?
    private var lastValidObjectPos: SIMD3<Float>?
    
    /// Returns a point a bit ahead of the headset, with vertical offset, given a Transform.
    private func headsetVirtualPosition(from pose: Transform) -> SIMD3<Float> {
        let forward = normalize(SIMD3<Float>(-pose.matrix.columns.2.x, -pose.matrix.columns.2.y, -pose.matrix.columns.2.z))
        var pos = pose.translation + forward * headsetForwardOffset
        pos.y += headsetYOffset
        return pos
    }
    
    private func adjustedObjectPosition(for step: Step, base: SIMD3<Float>) -> SIMD3<Float> {
        let dx: Float = 0.2
        let dy: Float = 0.25
        switch step {
        case .straight1:
            return base
        case .straight2:
            return SIMD3(base.x + dx, base.y, base.z)
        case .straight3:
            return SIMD3(base.x, base.y + dy, base.z)
        case .straight4:
            return SIMD3(base.x - dx, base.y, base.z)
        default:
            return base
        }
    }
    
    private func adjustedHeadsetPosition(for step: Step, base: SIMD3<Float>) -> SIMD3<Float> {
        switch step {
        case .zigzagBeginner, .zigzagAdvanced:
            // Lower the start dot for zigzag tasks
            return SIMD3(base.x, base.y - 0.05, base.z) // 10cm lower
        default:
            // Keep original position for straight line tasks
            return base
        }
    }
    
    private func getLinePositions(devicePose: DeviceAnchor, virtualPoint: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>) {
        // Check if we have stored finger-based positions
        let storedHeadsetPos: SIMD3<Float>?
        let storedObjectPos: SIMD3<Float>?
        
        switch dataManager.currentStep {
        case .straight1:
            storedHeadsetPos = dataManager.straight1HeadsetPosition
            storedObjectPos = dataManager.straight1ObjectPosition
        case .straight2:
            storedHeadsetPos = dataManager.straight2HeadsetPosition
            storedObjectPos = dataManager.straight2ObjectPosition
        case .straight3:
            storedHeadsetPos = dataManager.straight3HeadsetPosition
            storedObjectPos = dataManager.straight3ObjectPosition
        case .straight4:
            storedHeadsetPos = dataManager.straight4HeadsetPosition
            storedObjectPos = dataManager.straight4ObjectPosition
        case .zigzagBeginner:
            storedHeadsetPos = dataManager.zigzagBeginnerHeadsetPosition
            storedObjectPos = dataManager.zigzagBeginnerObjectPosition
        case .zigzagAdvanced:
            storedHeadsetPos = dataManager.zigzagAdvancedHeadsetPosition
            storedObjectPos = dataManager.zigzagAdvancedObjectPosition
        }
        
        // If we have stored positions (from finger stability), use them
        if let headsetPos = storedHeadsetPos, let objectPos = storedObjectPos {
            // Update cache
            lastValidHeadsetPos = headsetPos
            lastValidObjectPos = objectPos
            // print("Using stored positions: Headset \(headsetPos), Object \(objectPos)")
            return (headsetPos, objectPos)
        } else if let cachedHeadset = lastValidHeadsetPos, let cachedObject = lastValidObjectPos {
            // Fallback to cache if DataManager is temporarily nil
            print("⚠️ DataManager positions nil, using cached positions to prevent jump.")
            return (cachedHeadset, cachedObject)
        } else {
            print("⚠️ Falling back to dynamic calculation! StoredHeadset: \(String(describing: storedHeadsetPos)), StoredObject: \(String(describing: storedObjectPos))")
            // Otherwise, use original calculation method
            let pose = Transform(matrix: devicePose.originFromAnchorTransform)
            let headsetPos = headsetVirtualPosition(from: pose)
            let objectPos = adjustedObjectPosition(for: dataManager.currentStep, base: virtualPoint)
            let adjustedHeadsetPos = adjustedHeadsetPosition(for: dataManager.currentStep, base: headsetPos)
            return (adjustedHeadsetPos, objectPos)
        }
    }
    
    @MainActor
    init(
        using worldInfo: WorldTrackingProvider,
        dataManager: DataManager,
        virtualPoint: SIMD3<Float>,
        fingerTracker: FingerTracker
    ) {
        self.worldInfo = worldInfo
        self.dataManager = dataManager
        self.virtualPoint = [virtualPoint.x, virtualPoint.y, virtualPoint.z]
        
        let root = Entity()
        root.transform = Transform() // Identity transform at origin
        root.isEnabled = false // Start with visualizations hidden
        self.entity = root
        
        self.straightLineRenderer1 = StraightLineRenderer(parentEntity: root)
        self.straightLineRenderer2 = StraightLineRenderer(parentEntity: root)
        self.straightLineRenderer3 = StraightLineRenderer(parentEntity: root)
        self.straightLineRenderer4 = StraightLineRenderer(parentEntity: root)
        self.zigZagLineRendererBeginner = ZigZagLineRenderer(parentEntity: root)
        self.zigZagLineRendererAdvanced = ZigZagLineRenderer(parentEntity: root)
        self.fingerTracker = fingerTracker
        self.distanceCalculator = DistanceCalculator(worldInfo: worldInfo)
        
       // createWindowPane()
       // createInstructionText()
    }
    
    func hideAllButCurrentStepDots() {
        switch dataManager.currentStep {
        case .straight1:
            straightLineRenderer1.showAllDots()
            straightLineRenderer2.hideAllDots()
            straightLineRenderer3.hideAllDots()
            straightLineRenderer4.hideAllDots()
            zigZagLineRendererBeginner.hideAllDots()
            zigZagLineRendererAdvanced.hideAllDots()
        case .straight2:
            straightLineRenderer1.hideAllDots()
            straightLineRenderer2.showAllDots()
            straightLineRenderer3.hideAllDots()
            straightLineRenderer4.hideAllDots()
            zigZagLineRendererBeginner.hideAllDots()
            zigZagLineRendererAdvanced.hideAllDots()
        case .straight3:
            straightLineRenderer1.hideAllDots()
            straightLineRenderer2.hideAllDots()
            straightLineRenderer3.showAllDots()
            straightLineRenderer4.hideAllDots()
            zigZagLineRendererBeginner.hideAllDots()
            zigZagLineRendererAdvanced.hideAllDots()
        case .straight4:
            straightLineRenderer1.hideAllDots()
            straightLineRenderer2.hideAllDots()
            straightLineRenderer3.hideAllDots()
            straightLineRenderer4.showAllDots()
            zigZagLineRendererBeginner.hideAllDots()
            zigZagLineRendererAdvanced.hideAllDots()
        case .zigzagBeginner:
            straightLineRenderer1.hideAllDots()
            straightLineRenderer2.hideAllDots()
            straightLineRenderer3.hideAllDots()
            straightLineRenderer4.hideAllDots()
            zigZagLineRendererBeginner.showAllDots()
            zigZagLineRendererAdvanced.hideAllDots()
        case .zigzagAdvanced:
            straightLineRenderer1.hideAllDots()
            straightLineRenderer2.hideAllDots()
            straightLineRenderer3.hideAllDots()
            straightLineRenderer4.hideAllDots()
            zigZagLineRendererBeginner.hideAllDots()
            zigZagLineRendererAdvanced.showAllDots()
        }
    }
    
    func unfreezeAllDots() {
        straightLineRenderer1.unfreezeDots()
        straightLineRenderer2.unfreezeDots()
        straightLineRenderer3.unfreezeDots()
        straightLineRenderer4.unfreezeDots()
        zigZagLineRendererBeginner.unfreezeDots()
        zigZagLineRendererAdvanced.unfreezeDots()
    }
    
    func showVisualizations() {
        // Make the entity visible
        entity.isEnabled = true
        
        // Force an update to position the line with stored finger-based positions
        if let devicePose = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let offset = SIMD3<Float>(0, -0.20, -0.6)
            let pose = Transform(matrix: devicePose.originFromAnchorTransform)
            let worldPos = SIMD3<Float>(pose.translation.x + offset.x, 
                                      pose.translation.y + offset.y, 
                                      pose.translation.z + offset.z)
            update(virtualPoint: worldPos)
        }
        
        // Show the dots for the current step
        hideAllButCurrentStepDots()
        
        // Show initial instructions
        showInitialInstructions()
    }
    
    func hideVisualizations() {
        // Hide all dots and make entity invisible
        straightLineRenderer1.hideAllDots()
        straightLineRenderer2.hideAllDots()
        straightLineRenderer3.hideAllDots()
        straightLineRenderer4.hideAllDots()
        zigZagLineRendererBeginner.hideAllDots()
        zigZagLineRendererAdvanced.hideAllDots()
        
        // Hide instructions as well
        hideStartInstruction()
        hideEndInstruction()
        
        // Make the entire entity invisible
        entity.isEnabled = false
    }
    
    func update(virtualPoint newVirtualPoint: SIMD3<Float>) {
        
        // Only update if entity is enabled (i.e., visualizations should be shown)
        guard entity.isEnabled else { return }
        
        hideAllButCurrentStepDots()
        
        virtualPoint = newVirtualPoint
        
        // Update instruction positions to follow the moving dots

        
        guard let devicePose = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            // ARKit tracking lost - don't hide dots for attempts 2+, just return
            if dataManager.currentAttempt > 1 {
                // Keep dots visible even when tracking is lost
                switch dataManager.currentStep {
                case .straight1:
                    straightLineRenderer1.showAllDots()
                case .straight2:
                    straightLineRenderer2.showAllDots()
                case .straight3:
                    straightLineRenderer3.showAllDots()
                case .straight4:
                    straightLineRenderer4.showAllDots()
                case .zigzagBeginner:
                    zigZagLineRendererBeginner.showAllDots()
                case .zigzagAdvanced:
                    zigZagLineRendererAdvanced.showAllDots()
                }
            } else {
                // First attempt: hide dots when tracking is lost
                switch dataManager.currentStep {
                case .straight1:
                    straightLineRenderer1.hideAllDots()
                case .straight2:
                    straightLineRenderer2.hideAllDots()
                case .straight3:
                    straightLineRenderer3.hideAllDots()
                case .straight4:
                    straightLineRenderer4.hideAllDots()
                case .zigzagBeginner:
                    zigZagLineRendererBeginner.hideAllDots()
                case .zigzagAdvanced:
                    zigZagLineRendererAdvanced.hideAllDots()
                }
            }
            return
        }
        
        let pose = Transform(matrix: devicePose.originFromAnchorTransform)
        
        // Use stored positions from finger-based calculation if available, otherwise use original logic
        let (adjustedHeadsetPos, objectPos) = getLinePositions(devicePose: devicePose, virtualPoint: virtualPoint)
        
        // Move headsetPos and objectPos closer to each other by t
        let t1: Float = 0
        let t2: Float = 0
        let closerHeadsetPos = simd_mix(adjustedHeadsetPos, objectPos, SIMD3<Float>(repeating: t1))
        var closerObjectPos = simd_mix(objectPos, adjustedHeadsetPos, SIMD3<Float>(repeating: t2))
        
        // ANIMATION LOGIC:
        
        // ANIMATION LOGIC:
        
        if isTracing {
            // FORWARD ANIMATION (Slide Out)
            
            // Start or continue animation
            if animationStartTime == nil {
                 animationStartTime = CACurrentMediaTime()
                 isAnimationComplete = false
            }
            
            if let startTime = animationStartTime {
                let now = CACurrentMediaTime()
                let duration: TimeInterval = 10.0
                let elapsed = now - startTime
                
                if elapsed < duration {
                    // Calculate progress (0.0 to 1.0) with ease-out curve
                    let rawProgress = Float(elapsed / duration)
                    let progress = 1.0 - pow(1.0 - rawProgress, 3) // Cubic ease-out
                    
                    // Interpolate position: Start at Green Dot, end at Red Dot
                    closerObjectPos = simd_mix(closerHeadsetPos, closerObjectPos, SIMD3<Float>(repeating: progress))
                    isAnimationComplete = false
                } else {
                    // Animation complete
                    isAnimationComplete = true
                }
                // If elapsed >= duration, closerObjectPos is already at the target (progress = 1.0)
            }
        } else {
            // Not tracing - collapse the line so only the start dot is visible
            animationStartTime = nil
            isAnimationComplete = false
            closerObjectPos = closerHeadsetPos
        }
        
        switch dataManager.currentStep {
        case .straight1:
            straightLineRenderer1.updateDottedLine(
                from: closerHeadsetPos,
                to: closerObjectPos,
                relativeTo: entity
            )
        case .straight2:
            straightLineRenderer2.updateDottedLine(
                from: closerHeadsetPos,
                to: closerObjectPos,
                relativeTo: entity
            )
        case .straight3:
            straightLineRenderer3.updateDottedLine(
                from: closerHeadsetPos,
                to: closerObjectPos,
                relativeTo: entity
            )
        case .straight4:
            straightLineRenderer4.updateDottedLine(
                from: closerHeadsetPos,
                to: closerObjectPos,
                relativeTo: entity
            )
        case .zigzagBeginner:
            zigZagLineRendererBeginner.updateZigZagLine(
                from: closerHeadsetPos,
                to: closerObjectPos,
                relativeTo: entity,
                amplitude: 0.05,
                frequency: 2
            )
        case .zigzagAdvanced:
            zigZagLineRendererAdvanced.updateZigZagLine(
                from: closerHeadsetPos,
                to: closerObjectPos,
                relativeTo: entity,
                amplitude: 0.05,
                frequency: 4
            )
        }
        
        
        // Update instruction positions to follow the moving dots (do this AFTER updating dots)
        updateInstructionPositions()
    }
    
    func startTracing() {
        fingerTracker.startTracing()
        isTracing = true
        
        // Hide start instruction and show end instruction
        hideStartInstruction()
        showEndInstruction()
       // updateInstructionText()
    }
    
    func stopTracing() {
        fingerTracker.stopTracing()
        isTracing = false
        
        // Hide end instruction when tracing stops
        hideEndInstruction()
        
        let stepType = dataManager.currentStep
        // userTrace now stores tuples of (position, timestamp)
        let userTrace: [(SIMD3<Float>, TimeInterval)] = fingerTracker.getTimedTracePoints()
        
        dataManager.setUserTrace(userTrace, for: stepType)
       // updateInstructionText()
    }
    
    func clearTrace() {
        fingerTracker.clearTrace()
        isTracing = false
        
        // Reset instructions to initial state - only show start instruction if not tracing
        hideEndInstruction()
        if !isTracing {
            showStartInstruction()
        }
       // updateInstructionText()
    }
    
    func updateFingerTrace(fingerWorldPos: SIMD3<Float>) {
        fingerTracker.updateFingerTrace(
            fingerWorldPos: fingerWorldPos,
            relativeTo: entity
        )
    }
    
    func isFingerNearFirstDot(_ fingerWorldPos: SIMD3<Float>, threshold: Float = 0.0075) -> Bool {
        let firstDotWorldPos: SIMD3<Float>?
        switch dataManager.currentStep {
        case .straight1:
            firstDotWorldPos = straightLineRenderer1.getFirstDotWorldPosition(relativeTo: entity)
        case .straight2:
            firstDotWorldPos = straightLineRenderer2.getFirstDotWorldPosition(relativeTo: entity)
        case .straight3:
            firstDotWorldPos = straightLineRenderer3.getFirstDotWorldPosition(relativeTo: entity)
        case .straight4:
            firstDotWorldPos = straightLineRenderer4.getFirstDotWorldPosition(relativeTo: entity)
        case .zigzagBeginner:
            firstDotWorldPos = zigZagLineRendererBeginner.getFirstDotWorldPosition(relativeTo: entity)
        case .zigzagAdvanced:
            firstDotWorldPos = zigZagLineRendererAdvanced.getFirstDotWorldPosition(relativeTo: entity)
        }
        guard let firstDot = firstDotWorldPos else { return false }
        return simd_distance(fingerWorldPos, firstDot) < threshold
    }
    
    func isFingerNearLastDot(_ fingerWorldPos: SIMD3<Float>, threshold: Float = 0.0075) -> Bool {
        let lastDotWorldPos: SIMD3<Float>?
        switch dataManager.currentStep {
        case .straight1:
            lastDotWorldPos = straightLineRenderer1.getLastDotWorldPosition(relativeTo: entity)
        case .straight2:
            lastDotWorldPos = straightLineRenderer2.getLastDotWorldPosition(relativeTo: entity)
        case .straight3:
            lastDotWorldPos = straightLineRenderer3.getLastDotWorldPosition(relativeTo: entity)
        case .straight4:
            lastDotWorldPos = straightLineRenderer4.getLastDotWorldPosition(relativeTo: entity)
        case .zigzagBeginner:
            lastDotWorldPos = zigZagLineRendererBeginner.getLastDotWorldPosition(relativeTo: entity)
        case .zigzagAdvanced:
            lastDotWorldPos = zigZagLineRendererAdvanced.getLastDotWorldPosition(relativeTo: entity)
        }
        guard let lastDot = lastDotWorldPos else { return false }
        return simd_distance(fingerWorldPos, lastDot) < threshold
    }
    
    func getTracePoints() -> [SIMD3<Float>] {
        let traceWithTime = fingerTracker.getTimedTracePoints()
        return traceWithTime.map { $0.0 }
    }
    
    func getTraceLength() -> Float {
        let positions = getTracePoints()
        guard positions.count > 1 else { return 0 }
        var length: Float = 0
        for i in 1..<positions.count {
            length += simd_distance(positions[i], positions[i-1])
        }
        return length
    }
    
    func showZigZagLine() {
        if dataManager.currentStep == .zigzagBeginner {
            zigZagLineRendererBeginner.showAllDots()
        } else {
            zigZagLineRendererAdvanced.showAllDots()
        }
    }

    func hideZigZagLine() {
        if dataManager.currentStep == .zigzagBeginner {
            zigZagLineRendererBeginner.hideAllDots()
        } else {
            zigZagLineRendererAdvanced.hideAllDots()
        }
    }
    
    func updateDistance(_ distance: Float) {
        print(String(format: "Distance to white line: %.3f m", distance))
        let newDistance = Double(distance)
        let now = CACurrentMediaTime()
        if abs(newDistance - distanceObject) > 0.005,
           now - lastTextUpdateTime >= 0.1 {
            distanceObject = newDistance
            lastTextUpdateTime = now
          //  updateInstructionText()
        }
    }
    
    func distanceFromFinger(to fingerWorldPos: SIMD3<Float>) -> Float? {
        if let devicePose = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let pose = Transform(matrix: devicePose.originFromAnchorTransform)
            let headsetPos = headsetVirtualPosition(from: pose)
            let objectPos = virtualPoint
            
            let t1: Float = 0
            let t2: Float = 0
            let closerHeadsetPos = simd_mix(headsetPos, objectPos, SIMD3<Float>(repeating: t1))
            var closerObjectPos = simd_mix(objectPos, headsetPos, SIMD3<Float>(repeating: t2))
            
            return distanceCalculator.distanceFromFingerToLine(
                fingerWorldPos: fingerWorldPos,
                objectWorldPos: closerHeadsetPos,
            )
        }
        return nil
    }
    
    func resetVisualizations() {
        switch dataManager.currentStep {
        case .straight1:
            straightLineRenderer1.hideAllDots()
        case .straight2:
            straightLineRenderer2.hideAllDots()
        case .straight3:
            straightLineRenderer3.hideAllDots()
        case .straight4:
            straightLineRenderer4.hideAllDots()
        case .zigzagBeginner:
            zigZagLineRendererBeginner.hideAllDots()
        case .zigzagAdvanced:
            zigZagLineRendererAdvanced.hideAllDots()
        }
        fingerTracker.clearTrace()
        fingerTracker.stopTracing()
        isTracing = false
        
        // Hide all instructions when resetting
        hideStartInstruction()
        hideEndInstruction()
       // updateInstructionText()
    }
    
    func showInitialInstructions() {
        // Show start instruction for the current step when ready
        if !isTracing {
            showStartInstruction()
        }
    }
    
    private func updateInstructionPositions() {
        // Update start instruction position if it exists
        if let startInstruction = startInstructionEntity,
           let firstDotPos = getFirstDotPosition() {
            startInstruction.position = firstDotPos + SIMD3<Float>(0, 0.03, 0)
            orientWindowTowardsUser(startInstruction)
        }
        
        // Update end instruction position if it exists
        if let endInstruction = endInstructionEntity,
           let lastDotPos = getLastDotPosition() {
            endInstruction.position = lastDotPos + SIMD3<Float>(0, 0.03, 0)
            orientWindowTowardsUser(endInstruction)
        }
    }
    
    private func createInstructionWindow(text: String, textColor: UIColor = .white) -> Entity {
        let container = Entity()
        
        // Create text only (no background panel)
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.0005,
            font: .systemFont(ofSize: 0.01, weight: .black), // Changed to black weight for maximum boldness
            containerFrame: CGRect(x: 0, y: 0, width: 150, height: 30),
            alignment: .center
        )
        
        var textMaterial = UnlitMaterial()
        textMaterial.color = .init(tint: textColor)
        
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        
        // Center the text
        let textBounds = textMesh.bounds
        textEntity.position = SIMD3<Float>(
            -textBounds.center.x,
            -textBounds.center.y,
            -textBounds.center.z
        )
        
        container.addChild(textEntity)
        
        return container
    }
    
    func showStartInstruction() {
        hideStartInstruction() // Remove any existing instruction
        
        // Ensure we have a valid first dot position before showing instruction
        guard let firstDotPos = getFirstDotPosition() else { 
            // If no position available, try again after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showStartInstruction()
            }
            return 
        }
        
        let instructionWindow = createInstructionWindow(
            text: "Starting point",
            textColor: .systemGreen
        )
        
        instructionWindow.position = firstDotPos + SIMD3<Float>(0, 0.03, 0) // Closer to the dot
        
        // Make it face the user
        orientWindowTowardsUser(instructionWindow)
        
        entity.addChild(instructionWindow)
        startInstructionEntity = instructionWindow
    }
    
    func hideStartInstruction() {
        startInstructionEntity?.removeFromParent()
        startInstructionEntity = nil
    }
    
    func showEndInstruction() {
        hideEndInstruction() // Remove any existing instruction
        
        // Ensure we have a valid last dot position before showing instruction
        guard let lastDotPos = getLastDotPosition() else { 
            // If no position available, try again after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showEndInstruction()
            }
            return 
        }
        
        let instructionWindow = createInstructionWindow(
            text: "Ending point",
            textColor: .systemRed
        )
        
        instructionWindow.position = lastDotPos + SIMD3<Float>(0, 0.03, 0) // Closer to the dot
        
        // Make it face the user
        orientWindowTowardsUser(instructionWindow)
        
        entity.addChild(instructionWindow)
        endInstructionEntity = instructionWindow
    }
    
    func hideEndInstruction() {
        endInstructionEntity?.removeFromParent()
        endInstructionEntity = nil
    }
    
    private func orientWindowTowardsUser(_ window: Entity) {
        if let devicePose = worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let devicePos = SIMD3<Float>(
                devicePose.originFromAnchorTransform.columns.3.x,
                devicePose.originFromAnchorTransform.columns.3.y,
                devicePose.originFromAnchorTransform.columns.3.z
            )
            let windowPos = window.position
            let lookDirection = normalize(devicePos - windowPos)
            
            // Calculate rotation to face the user
            let forward = SIMD3<Float>(0, 0, 1)
            let angle = acos(simd_dot(forward, lookDirection))
            let axis = simd_cross(forward, lookDirection)
            
            if simd_length(axis) > 0.001 {
                let normalizedAxis = normalize(axis)
                window.transform.rotation = simd_quatf(angle: angle, axis: normalizedAxis)
            }
        }
    }
    
    private func getFirstDotPosition() -> SIMD3<Float>? {
        switch dataManager.currentStep {
        case .straight1:
            return straightLineRenderer1.getFirstDotWorldPosition(relativeTo: entity)
        case .straight2:
            return straightLineRenderer2.getFirstDotWorldPosition(relativeTo: entity)
        case .straight3:
            return straightLineRenderer3.getFirstDotWorldPosition(relativeTo: entity)
        case .straight4:
            return straightLineRenderer4.getFirstDotWorldPosition(relativeTo: entity)
        case .zigzagBeginner:
            return zigZagLineRendererBeginner.getFirstDotWorldPosition(relativeTo: entity)
        case .zigzagAdvanced:
            return zigZagLineRendererAdvanced.getFirstDotWorldPosition(relativeTo: entity)
        }
    }
    
    private func getLastDotPosition() -> SIMD3<Float>? {
        switch dataManager.currentStep {
        case .straight1:
            return straightLineRenderer1.getLastDotWorldPosition(relativeTo: entity)
        case .straight2:
            return straightLineRenderer2.getLastDotWorldPosition(relativeTo: entity)
        case .straight3:
            return straightLineRenderer3.getLastDotWorldPosition(relativeTo: entity)
        case .straight4:
            return straightLineRenderer4.getLastDotWorldPosition(relativeTo: entity)
        case .zigzagBeginner:
            return zigZagLineRendererBeginner.getLastDotWorldPosition(relativeTo: entity)
        case .zigzagAdvanced:
            return zigZagLineRendererAdvanced.getLastDotWorldPosition(relativeTo: entity)
        }
    }
}

