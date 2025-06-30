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
        // The review state holds the complete analysis result, including scaleFactor
        case review(videoURL: URL, result: VideoAnalysisResult)
        case completed(Double)
        case error(String)
    }

    @Published var appState: AppState = .idle
    private var videoProcessor: VideoProcessor?

    func finishReview(andShowResultsFrom editedResults: [FrameAnalysis]) {
        let maxSpeed = editedResults.compactMap { $0.speedKPH }.max() ?? 0.0
        self.appState = .completed(maxSpeed)
    }
    
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
                let analysisResult = try await videoProcessor?.processVideo(progressHandler: { newProgress in
                    self.appState = .processing(newProgress)
                })
                
                if let result = analysisResult {
                    self.appState = .review(videoURL: videoURL, result: result)
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
