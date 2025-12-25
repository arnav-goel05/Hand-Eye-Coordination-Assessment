/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The main user interface.
*/

import SwiftUI
import ARKit
import RealityKit
import UniformTypeIdentifiers

extension DateFormatter {
    static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

// Custom checkmark shape for animated drawing effect
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Draw checkmark: short line going down-right, then long line going up-right
        let shortStart = CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY)
        let corner = CGPoint(x: rect.minX + rect.width * 0.4, y: rect.maxY - rect.height * 0.2)
        let longEnd = CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + rect.height * 0.15)
        
        path.move(to: shortStart)
        path.addLine(to: corner)
        path.addLine(to: longEnd)
        
        return path
    }
}

struct HomeView: View {
    @Bindable var appState: AppState
    let immersiveSpaceIdentifier: String
    
    let referenceObjectUTType = UTType("com.apple.arkit.referenceobject")!
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject var dataManager: DataManager
    
    @State private var fileImporterIsOpen = false
    
    @State var selectedReferenceObjectID: ReferenceObject.ID?
    
    @State private var titleText = ""
    @State private var isTitleFinished = false
    private let finalTitle = "Hand-Eye Coordination Assessment"
    
    var body: some View {
        NavigationStack {
            VStack {
                if appState.canEnterImmersiveSpace {
                    if !appState.isImmersiveSpaceOpened {
                        // Show loading view while waiting for immersive space to open
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                    } else {
                        // Container view for consistent overlay application
                        ZStack {
                            // Calibration screens
                            if !dataManager.calibrationComplete {
                                VStack {
                                    switch dataManager.calibrationPhase {
                                    case .waitingForHead, .waitingForOneHand:
                                        if !dataManager.leftHandDetected && !dataManager.rightHandDetected {
                                            // No hands detected
                                            Text("Please show your hand which you will use for the application")
                                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                                .padding()
                                                .transition(.opacity)
                                                .id("noHands")
                                        } else if dataManager.leftHandDetected && dataManager.rightHandDetected {
                                            // Both hands detected
                                            Text("I can see both hands, please just show one hand")
                                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                                .padding()
                                                .transition(.opacity)
                                                .id("bothHands")
                                        }
                                        
                                    case .holdingSteady:
                                        if let selectedHand = dataManager.selectedHand {
                                            let handName = selectedHand == .left ? "Left" : "Right"
                                            Text("\(handName) hand detected")
                                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                                .padding()
                                                .transition(.opacity)
                                                .id("handDetected-\(handName)")
                                        }
                                        
                                    case .countingDown:
                                        VStack(spacing: 20) {
                                            // Circular progress animation
                                            ZStack {
                                                // Background circle
                                                Circle()
                                                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                                                    .frame(width: 120, height: 120)
                                                
                                                // Animated progress circle
                                                Circle()
                                                    .trim(from: 0, to: dataManager.calibrationProgress)
                                                    .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                                    .frame(width: 120, height: 120)
                                                    .rotationEffect(.degrees(-90))  // Start from top
                                                    .animation(.linear(duration: 0.016), value: dataManager.calibrationProgress)
                                            }
                                        }
                                        .transition(.opacity)
                                        .id("countingDown")
                                        
                                    case .complete:
                                        // Circle with checkmark - animated entrance
                                        ZStack {
                                            // Completed circle - bounces in
                                            Circle()
                                                .stroke(Color.green, lineWidth: 8)
                                                .frame(width: 120, height: 120)
                                                .scaleEffect(dataManager.calibrationPhase == .complete ? 1.0 : 0.0)
                                                .animation(.spring(response: 0.6, dampingFraction: 0.5, blendDuration: 0), value: dataManager.calibrationPhase)
                                            
                                            // Animated checkmark - draws itself progressively
                                            CheckmarkShape()
                                                .trim(from: 0, to: dataManager.checkmarkProgress)
                                                .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                                                .frame(width: 60, height: 60)
                                        }
                                        .transition(.opacity)
                                        .id("complete")
                                    }
                                }
                                .animation(.easeInOut(duration: 0.5), value: dataManager.calibrationPhase)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.leftHandDetected)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.rightHandDetected)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                            }
                            // Show step completion checkmark animation
                            else if dataManager.isShowingStepComplete {
                                VStack {
                                    ZStack {
                                        Circle()
                                            .stroke(Color.green, lineWidth: 6)
                                            .frame(width: 100, height: 100)
                                        
                                        CheckmarkShape()
                                            .trim(from: 0, to: dataManager.stepCompleteProgress)
                                            .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                                            .frame(width: 65, height: 65)
                                    }
                                    
                                    Text("Step Complete!")
                                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                        .padding(.top, 15)
                                }
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingStepComplete)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.assessmentCompleted)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isTracing)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingCompletionCountdown)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerStable)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerBeingTracked)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                                .id("stepComplete")
                            }
                            // Show "Thank you" message when assessment is completed
                            else if dataManager.assessmentCompleted {
                                VStack {
                                    Text("Thank You")
                                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.assessmentCompleted)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isTracing)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingCompletionCountdown)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingStepComplete)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                                .id("thankYou")
                                .onAppear {
                                    // Automatically export all data when thank you message appears
                                    exportAllDataToDocuments()
                                }
                            } else if dataManager.isTracing && dataManager.isFingerTooCloseForFinish {
                                // When tracing and the finger is too close to the headset to finish,
                                // instruct the user to move the finger forward (away from headset)
                                VStack {
                                    Text("Index finger is too close to finish")
                                        .font(.system(size: 28, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerTooCloseForFinish)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                                .id("fingerTooCloseFinish")

                            } else if dataManager.isTracing && dataManager.isShowingCompletionCountdown {
                                // Show completion countdown when finger has been still for 2 seconds during tracing
                                VStack {
                                    Text("Hold steady to finish")
                                        .font(.system(size: 28, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                    Text("\(dataManager.tracingStabilityCountdown)")
                                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingCompletionCountdown)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.tracingStabilityCountdown)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isTracing)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerStable)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.assessmentCompleted)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingStepComplete)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                                .id("holdToFinish-\(dataManager.tracingStabilityCountdown)")
                            } else if dataManager.isTracing || dataManager.isFingerStable {
                                // Show attempt counter when tracing (but not showing completion countdown) or when finger is stable
                                VStack {
                                    if dataManager.isTracing && !dataManager.isAnimationComplete {
                                        Text("Follow the red dot")
                                            .font(.system(size: 32, weight: .medium, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.bottom)
                                    }
                                    
                                    Text("\(dataManager.currentAttempt) / 10")
                                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.bottom)
                                    
                                    if dataManager.isAnimationComplete {
                                        Button("Stop Tracing Now") {
                                            dataManager.forceStopTracing = true
                                        }
                                    }
                                }
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.currentAttempt)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isTracing)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerStable)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingCompletionCountdown)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerBeingTracked)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerTooFar)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.assessmentCompleted)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingStepComplete)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                                .id("attemptCounter-\(dataManager.currentAttempt)")
                            } else if !dataManager.isFingerBeingTracked {
                                // Show instruction when no finger is detected
                                VStack {
                                    Text("Please show your index finger to start the test")
                                        .font(.system(size: 32, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerBeingTracked)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerTooFar)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerStable)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isTracing)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.currentAttempt)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.assessmentCompleted)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingStepComplete)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                                .id("showFinger")
                            } else if dataManager.isFingerTooFar && !dataManager.isFingerStable {
                                // Show instruction when finger is detected but too far
                                VStack {
                                    Text("Bring the index finger closer to you")
                                        .font(.system(size: 32, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                    Button("Start Tracing Now") {
                                        dataManager.forceStartTracing = true
                                    }
                                }
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerTooFar)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerBeingTracked)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerStable)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isTracing)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.currentAttempt)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.assessmentCompleted)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingStepComplete)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                                .id("bringCloser")
                            } else if dataManager.isFingerBeingTracked && !dataManager.isFingerStable {
                                // Show countdown when finger is tracked but not yet stable
                                VStack {
                                    Text("Hold steady...")
                                        .font(.system(size: 28, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("\(dataManager.stabilityCountdown)")
                                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerStable)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerTooFar)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isFingerBeingTracked)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.stabilityCountdown)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isTracing)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.currentAttempt)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.assessmentCompleted)
                                .animation(.easeInOut(duration: 0.5), value: dataManager.isShowingStepComplete)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                                .id("holdSteady-\(dataManager.stabilityCountdown)")
                            }
                            
                            // Hidden buttons for functionality (invisible but functional)
                            VStack {
                                if dataManager.isStepComplete(for: dataManager.currentStep) && !dataManager.assessmentCompleted {
                                    if dataManager.currentStep == .zigzagAdvanced {
                                        Button(action: {
                                            Task {
                                                await dismissImmersiveSpace()
                                                appState.didLeaveImmersiveSpace()
                                                openWindow(id: "Summary")
                                            }
                                        }) {
                                            Color.clear
                                        }
                                        .opacity(0)
                                        .allowsHitTesting(false)
                                    } else {
                                        Button(action: {
                                            Task {
                                                dataManager.nextStep()
                                            }
                                        }) {
                                            Color.clear
                                        }
                                        .opacity(0)
                                        .allowsHitTesting(false)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Show authorization/setup screen when immersive space is not available
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.08, green: 0.08, blue: 0.08))
                }
            }
            .onAppear {
                // Automatically start the assessment when the app loads
                if appState.canEnterImmersiveSpace && !appState.isImmersiveSpaceOpened {
                    Task {
                        switch await openImmersiveSpace(id: immersiveSpaceIdentifier) {
                        case .opened:
                            break
                        case .error:
                            print("An error occurred when trying to open the immersive space \(immersiveSpaceIdentifier)")
                        case .userCancelled:
                            print("The user declined opening immersive space \(immersiveSpaceIdentifier)")
                        @unknown default:
                            break
                        }
                    }
                }
            }
            .onChange(of: scenePhase, initial: true) {
                print("HomeView scene phase: \(scenePhase)")
                if scenePhase == .active {
                    Task {
                        // When returning from the background, check if the authorization has changed.
                        await appState.queryWorldSensingAuthorization()
                        
                        // Ensure immersive space is opened if it should be
                        if appState.canEnterImmersiveSpace && !appState.isImmersiveSpaceOpened {
                            switch await openImmersiveSpace(id: immersiveSpaceIdentifier) {
                            case .opened:
                                break
                            case .error:
                                print("An error occurred when trying to open the immersive space \(immersiveSpaceIdentifier)")
                            case .userCancelled:
                                print("The user declined opening immersive space \(immersiveSpaceIdentifier)")
                            @unknown default:
                                break
                            }
                        }
                    }
                }
            }
            .onChange(of: appState.providersStoppedWithError, { _, providersStoppedWithError in
                // Immediately close the immersive space if an error occurs.
                if providersStoppedWithError {
                    if appState.isImmersiveSpaceOpened {
                        Task {
                            await dismissImmersiveSpace()
                            appState.didLeaveImmersiveSpace()
                        }
                    }
                    
                    appState.providersStoppedWithError = false
                }
            })
            .task {
                // Start monitoring for changes in authorization, in case a person brings the
                // Settings app to the foreground and changes authorizations there.
                await appState.monitorSessionEvents()
            }
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
        
        // Process all task types - need to create a simple mapping
        let allSteps: [Step] = [.straight1, .straight2, .straight3, .straight4, .zigzagBeginner, .zigzagAdvanced]
        
        for step in allSteps {
            let taskName = stepToFilename(step)
            
            // Add guide dots first
            if let start = getHeadsetPosition(for: step), let end = getObjectPosition(for: step) {
                let guideDots: [SIMD3<Float>]
                
                switch step {
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
            let attempts = dataManager.getAttempts(for: step)
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
    
    private func stepToFilename(_ step: Step) -> String {
        switch step {
        case .straight1: return "straight1"
        case .straight2: return "straight2"
        case .straight3: return "straight3"
        case .straight4: return "straight4"
        case .zigzagBeginner: return "zigzagBeginner"
        case .zigzagAdvanced: return "zigzagAdvanced"
        }
    }
    
    private func getHeadsetPosition(for step: Step) -> SIMD3<Float>? {
        switch step {
        case .straight1: return dataManager.straight1HeadsetPosition
        case .straight2: return dataManager.straight2HeadsetPosition
        case .straight3: return dataManager.straight3HeadsetPosition
        case .straight4: return dataManager.straight4HeadsetPosition
        case .zigzagBeginner: return dataManager.zigzagBeginnerHeadsetPosition
        case .zigzagAdvanced: return dataManager.zigzagAdvancedHeadsetPosition
        }
    }
    
    private func getObjectPosition(for step: Step) -> SIMD3<Float>? {
        switch step {
        case .straight1: return dataManager.straight1ObjectPosition
        case .straight2: return dataManager.straight2ObjectPosition
        case .straight3: return dataManager.straight3ObjectPosition
        case .straight4: return dataManager.straight4ObjectPosition
        case .zigzagBeginner: return dataManager.zigzagBeginnerObjectPosition
        case .zigzagAdvanced: return dataManager.zigzagAdvancedObjectPosition
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
        for i in 0...numberOfSegments {
            let t = Float(i) / Float(numberOfSegments)
            let point = start + direction * (lineLength * t)
            dots.append(point)
        }
        return dots
    }
    
    func generateZigZagGuideDots(start: SIMD3<Float>, end: SIMD3<Float>, amplitude: Float, frequency: Int, dotSpacing: Float = 0.001, maxDots: Int = 1000) -> [SIMD3<Float>] {
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
            let point = start + direction * (lineLength * t)
            
            let phase = Float(i) * Float(frequency) * .pi / Float(numberOfSegments)
            let amp = (i == 0 || i == numberOfSegments) ? 0 : amplitude * sin(phase)
            let offset = right * amp
            
            dots.append(point + offset)
        }
        return dots
    }
}

