import Foundation
import SwiftUI
import Combine
import CoreGraphics

@MainActor
class SmashSpeedViewModel: ObservableObject {
    
    private let monthlySmashLimit = 5

    @Published var smashesLeftText: String = ""
    @Published var canPerformSmash: Bool = true

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
    
    func updateUserState(userRecord: UserRecord?, isSubscribed: Bool) {
        if isSubscribed {
            smashesLeftText = "You have unlimited smashes with Pro."
            canPerformSmash = true
            return
        }
        
        guard let record = userRecord else {
            smashesLeftText = "Loading your data..."
            canPerformSmash = false
            return
        }
        
        let remaining = max(0, monthlySmashLimit - record.smashCount)
        if remaining == 1 {
            smashesLeftText = "You have 1 free analysis left this month."
        } else {
            smashesLeftText = "You have \(remaining) free analyses left this month."
        }
        
        canPerformSmash = remaining > 0
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

    func startProcessing(videoURL: URL, scaleFactor: Double) {
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

    func finishReview(andShowResultsFrom editedFrames: [FrameAnalysis], for userID: String?, videoURL: URL) {
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
