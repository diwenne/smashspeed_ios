//
//  SmashSpeedViewModel.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SmashSpeedViewModel: ObservableObject {
    
    // ✅ IMPROVED: The .processing state now holds a Progress object for the UI to observe.
    enum AppState {
        case idle
        case trimming(URL)
        case awaitingCalibration(URL)
        case processing(Progress)
        case review(videoURL: URL, result: VideoAnalysisResult)
        case completed(Double)
        case error(String)
    }
    
    @Published var appState: AppState = .idle
    
    private var videoProcessor: VideoProcessor?
    
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
        // ✅ IMPROVED: Create a Progress object to track the analysis.
        let progress = Progress(totalUnitCount: 100)
        appState = .processing(progress)
        
        Task {
            do {
                guard let modelHandler = try? YOLOv5ModelHandler() else {
                    appState = .error("Failed to load detection model.")
                    return
                }
                
                let tracker = ShuttlecockTracker(scaleFactor: scaleFactor)
                self.videoProcessor = VideoProcessor(videoURL: videoURL, modelHandler: modelHandler, tracker: tracker)
                
                // ✅ FIXED: Corrected the `if let` syntax and the progress handler logic.
                if let processor = self.videoProcessor {
                    if let result = try await processor.processVideo(progressHandler: { newProgress in
                        // Update the main progress object so the UI can see changes.
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
        
        // ✅ FIXED: Use `compactMap` to safely unwrap the optional boundingBox
        // and filter out frames that don't have a detection.
        let frameDataToSave = editedFrames.compactMap { frame -> FrameData? in
            guard let validBox = frame.boundingBox else {
                return nil // This will filter out this frame.
            }
            return FrameData(
                timestamp: frame.timestamp,
                speedKPH: frame.speedKPH ?? 0.0,
                boundingBox: CodableRect(from: validBox)
            )
        }
        
        if let userID = userID {
            // Use a simple state here; no need for a progress object for a quick upload.
            appState = .processing(Progress())
            
            Task {
                do {
                    let downloadURL = try await StorageManager.shared.uploadVideo(localURL: videoURL, for: userID)
                    
                    try HistoryViewModel.saveResult(
                        peakSpeedKph: maxSpeed,
                        for: userID,
                        videoURL: downloadURL.absoluteString,
                        frameData: frameDataToSave
                    )
                    
                    appState = .completed(maxSpeed)
                } catch {
                    let errorMessage = "Failed to upload video. Please try again.\nError: \(error.localizedDescription)"
                    appState = .error(errorMessage)
                }
            }
        } else {
            appState = .completed(maxSpeed)
        }
    }

    func reset() {
        videoProcessor = nil
        appState = .idle
    }
}
