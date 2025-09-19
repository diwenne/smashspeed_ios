import Foundation
import SwiftUI
import Combine
import CoreGraphics

@MainActor
class SmashSpeedViewModel: ObservableObject {
    
    private let monthlySmashLimit = 5
    @AppStorage("smashCount") private var smashCount: Int = 0
    @AppStorage("lastSmashMonth") private var lastSmashMonth: String = ""

    @Published var smashesLeftText: String = ""

    enum AppState {
        case idle
        case preparing
        case trimming(URL)
        case awaitingCalibration(URL)
        case processing(Progress)
        case review(videoURL: URL, result: VideoAnalysisResult)
        case completed(speed: Double, angle: Double?)
        case error(String)
        case limitReached
    }
    
    @Published var appState: AppState = .idle
    
    private var videoProcessor: VideoProcessor?
    
    func updateSmashesLeftDisplay(isSubscribed: Bool) {
        if isSubscribed {
            smashesLeftText = "You have unlimited smashes with Pro."
            return
        }
        
        checkAndResetMonthlyCountIfNeeded()
        let remaining = max(0, monthlySmashLimit - smashCount)
        if remaining == 1 {
            smashesLeftText = "You have 1 free analysis left this month."
        } else {
            smashesLeftText = "You have \(remaining) free analyses left this month."
        }
    }
    
    func canPerformSmash(isSubscribed: Bool) -> Bool {
        if isSubscribed {
            return true
        }
        checkAndResetMonthlyCountIfNeeded()
        return smashCount < monthlySmashLimit
    }
    
    private func incrementSmashCount(isSubscribed: Bool) {
        if !isSubscribed {
            smashCount += 1
        }
    }
    
    private func checkAndResetMonthlyCountIfNeeded() {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())
        let year = calendar.component(.year, from: Date())
        let currentMonthIdentifier = "month_\(month)_year_\(year)"
        
        if lastSmashMonth != currentMonthIdentifier {
            lastSmashMonth = currentMonthIdentifier
            smashCount = 0
        }
    }

    func videoSelected(url: URL) {
        appState = .trimming(url)
    }
    
    func videoTrimmed(url: URL) {
        appState = .awaitingCalibration(url)
    }
    
    func cancelCalibration() {
        reset()
    }

    // --- CHANGE #1: Added `isSubscribed` parameter to this function ---
    func startProcessing(videoURL: URL, scaleFactor: Double, isSubscribed: Bool) {
        let progress = Progress(totalUnitCount: 100)
        appState = .processing(progress)
        
        Task {
            do {
                guard let modelHandler = try? YOLOv5ModelHandler() else {
                    appState = .error("Failed to load detection model.")
                    return
                }
                
                let tracker = KalmanTracker(scaleFactor: scaleFactor)
                self.videoProcessor = VideoProcessor(videoURL: videoURL, modelHandler: modelHandler, tracker: tracker)

                if let processor = self.videoProcessor {
                    if let result = try await processor.processVideo(progressHandler: { newProgress in
                        progress.completedUnitCount = newProgress.completedUnitCount
                        progress.totalUnitCount = newProgress.totalUnitCount
                    }) {
                        // --- CHANGE #2: Credit is now used HERE, before showing the review screen ---
                        self.incrementSmashCount(isSubscribed: isSubscribed)
                        self.updateSmashesLeftDisplay(isSubscribed: isSubscribed)
                        
                        appState = .review(videoURL: videoURL, result: result)
                    }
                }
            } catch {
                appState = .error(error.localizedDescription)
            }
        }
    }
    
    func cancelProcessing() {
        videoProcessor?.cancelProcessing()
        reset()
    }

    func finishReview(andShowResultsFrom editedFrames: [FrameAnalysis], for userID: String?, videoURL: URL, isSubscribed: Bool) {
        // --- CHANGE #3: Removed the credit deduction logic from this function ---
        
        let maxSpeed = editedFrames.compactMap { $0.speedKPH }.max() ?? 0.0
        let angle = self.calculateSmashAngle(from: editedFrames)
        
        let frameDataToSave = editedFrames.compactMap { frame -> FrameData? in
            guard let validBox = frame.boundingBox else { return nil }
            return FrameData(
                timestamp: frame.timestamp,
                speedKPH: frame.speedKPH ?? 0.0,
                boundingBox: CodableRect(from: validBox)
            )
        }
        
        if let userID = userID {
            appState = .processing(Progress())
            
            Task {
                do {
                    let downloadURL = try await StorageManager.shared.uploadVideo(localURL: videoURL, for: userID)
                    
                    try HistoryViewModel.saveResult(
                        peakSpeedKph: maxSpeed,
                        angle: angle,
                        for: userID,
                        videoURL: downloadURL.absoluteString,
                        frameData: frameDataToSave
                    )
                    
                    appState = .completed(speed: maxSpeed, angle: angle)
                } catch {
                    let errorMessage = "Failed to upload video. Please try again.\nError: \(error.localizedDescription)"
                    appState = .error(errorMessage)
                }
            }
        } else {
            appState = .completed(speed: maxSpeed, angle: angle)
        }
    }

    func reset() {
        videoProcessor = nil
        appState = .idle
    }
    
    private func calculateSmashAngle(from frames: [FrameAnalysis]) -> Double? {
        let relevantPoints = frames.compactMap { frame -> CGPoint? in
            guard frame.boundingBox != nil, let point = frame.trackedPoint else { return nil }
            return point
        }

        guard relevantPoints.count > 1 else { return nil }

        var maxSequenceLength = 0
        var bestStartIndex = -1
        var currentStartIndex = 0
        
        for i in 0..<(relevantPoints.count - 1) {
            if relevantPoints[i+1].y > relevantPoints[i].y {
            } else {
                let currentSequenceLength = i - currentStartIndex + 1
                if currentSequenceLength > maxSequenceLength {
                    maxSequenceLength = currentSequenceLength
                    bestStartIndex = currentStartIndex
                }
                currentStartIndex = i + 1
            }
        }

        let lastSequenceLength = relevantPoints.count - currentStartIndex
        if lastSequenceLength > maxSequenceLength {
            maxSequenceLength = lastSequenceLength
            bestStartIndex = currentStartIndex
        }

        guard bestStartIndex != -1, maxSequenceLength > 1 else { return nil }

        let startPoint = relevantPoints[bestStartIndex]
        let endPoint = relevantPoints[bestStartIndex + maxSequenceLength - 1]

        let deltaY = endPoint.y - startPoint.y
        let deltaX = endPoint.x - startPoint.x
        
        let angleInRadians = atan2(deltaY, deltaX)
        let angleInDegrees = angleInRadians * 180 / .pi
        
        var finalAngle = abs(angleInDegrees)
        
        if finalAngle > 90 {
            finalAngle = 180 - finalAngle
        }
        
        return finalAngle
    }
}
