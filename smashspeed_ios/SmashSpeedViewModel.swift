//
//  SmashSpeedViewModel.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import Foundation
import SwiftUI
import AVFoundation

@MainActor
class SmashSpeedViewModel: ObservableObject {
    enum AppState {
        case idle
        case awaitingCalibration(URL)
        case processing(Progress)
        case review(videoURL: URL, results: [FrameAnalysis])
        case completed(Double)
        case error(String)
    }

    @Published var appState: AppState = .idle
    private var videoProcessor: VideoProcessor?

    // This function is now updated to accept the edited results
    func finishReview(andShowResultsFrom editedResults: [FrameAnalysis]) {
        // Find the maximum speed from the list of frame results
        let maxSpeed = editedResults.compactMap { $0.speedKPH }.max() ?? 0.0
        self.appState = .completed(maxSpeed)
    }
    
    // All other functions remain the same
    func videoSelected(url: URL) {
        self.appState = .awaitingCalibration(url)
    }
    
    func startProcessing(videoURL: URL, scaleFactor: Double) {
        let progress = Progress(totalUnitCount: 100)
        self.appState = .processing(progress)
        
        guard let modelHandler = YOLOv5ModelHandler() else {
            self.appState = .error("Failed to load CoreML model.")
            return
        }
        
        videoProcessor = VideoProcessor(
            videoURL: videoURL,
            modelHandler: modelHandler,
            tracker: ShuttlecockTracker(scaleFactor: scaleFactor)
        )
        
        Task {
            do {
                let analysisResults = try await videoProcessor?.processVideo(progressHandler: { newProgress in
                    self.appState = .processing(newProgress)
                })
                
                if let results = analysisResults {
                    self.appState = .review(videoURL: videoURL, results: results)
                } else {
                    self.appState = .error("Analysis failed to produce results.")
                }
            } catch {
                self.appState = .error("Processing failed: \(error.localizedDescription)")
            }
        }
    }
    
    func cancelCalibration() {
        self.appState = .idle
    }
    
    func reset() {
        videoProcessor?.cancelProcessing()
        videoProcessor = nil
        appState = .idle
    }
}
