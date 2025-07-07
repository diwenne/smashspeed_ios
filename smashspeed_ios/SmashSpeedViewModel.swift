//
//  SmashSpeedViewModel.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import Foundation
import SwiftUI
import Combine
import FirebaseStorage

@MainActor
class SmashSpeedViewModel: ObservableObject {
    
    enum AppState {
        case idle
        case awaitingCalibration(URL)
        case processing(Progress)
        case review(videoURL: URL, result: VideoAnalysisResult)
        case completed(Double)
        case error(String)
    }
    
    @Published var appState: AppState = .idle
    
    private var videoProcessor: VideoProcessor?
    
    func videoSelected(url: URL) {
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
                
                let tracker = ShuttlecockTracker(scaleFactor: scaleFactor)
                self.videoProcessor = VideoProcessor(videoURL: videoURL, modelHandler: modelHandler, tracker: tracker)
                
                if let processor = self.videoProcessor,
                   let result = try await processor.processVideo(progressHandler: { prog in
                    DispatchQueue.main.async {
                        progress.completedUnitCount = prog.completedUnitCount
                        progress.totalUnitCount = prog.totalUnitCount
                    }
                   }) {
                    appState = .review(videoURL: videoURL, result: result)
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
        
        if let userID = userID {
            // Re-use the .processing state to show a temporary "uploading" indicator
            let uploadProgress = Progress(totalUnitCount: 100)
            uploadProgress.completedUnitCount = 50 // You can adjust this to feel right
            appState = .processing(uploadProgress)
            
            Task {
                do {
                    let downloadURL = try await StorageManager.shared.uploadVideo(localURL: videoURL, for: userID)
                    try HistoryViewModel.saveResult(peakSpeedKph: maxSpeed, for: userID, videoURL: downloadURL.absoluteString)
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
