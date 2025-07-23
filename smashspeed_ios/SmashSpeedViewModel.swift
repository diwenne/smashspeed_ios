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
    
    enum AppState {
        case idle
        case trimming(URL)
        case awaitingCalibration(URL)
        case processing
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
        appState = .processing
        
        Task {
            do {
                guard let modelHandler = try? YOLOv5ModelHandler() else {
                    appState = .error("Failed to load detection model.")
                    return
                }
                
                let tracker = ShuttlecockTracker(scaleFactor: scaleFactor)
                self.videoProcessor = VideoProcessor(videoURL: videoURL, modelHandler: modelHandler, tracker: tracker)
                
                if let processor = self.videoProcessor,
                   // --- FIXED ---: Provide an empty closure instead of nil.
                   let result = try await processor.processVideo(progressHandler: { _ in }) {
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
        
        let frameDataToSave = editedFrames.map { frame in
            FrameData(
                timestamp: frame.timestamp,
                speedKPH: frame.speedKPH ?? 0.0, // Ensure non-optional value
                boundingBox: CodableRect(from: frame.boundingBox)
            )
        }
        
        if let userID = userID {
            appState = .processing
            
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
