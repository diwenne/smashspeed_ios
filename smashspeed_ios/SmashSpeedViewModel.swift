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
        case awaitingCalibration(URL)
        case processing(Progress)
        case review(videoURL: URL, result: VideoAnalysisResult)
        case completed(Double)
        case error(String)
    }
    
    @Published var appState: AppState = .idle
    
    private var videoProcessor: VideoProcessor?
    private var cancellables = Set<AnyCancellable>()

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
                
                if let processor = self.videoProcessor {
                    if let result = try await processor.processVideo(progressHandler: { prog in
                        DispatchQueue.main.async {
                            progress.completedUnitCount = prog.completedUnitCount
                            progress.totalUnitCount = prog.totalUnitCount
                        }
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

    func finishReview(andShowResultsFrom editedFrames: [FrameAnalysis], for userID: String?) {
        let maxSpeed = editedFrames.compactMap { $0.speedKPH }.max() ?? 0.0
        
        if let userID = userID {
            do {
                try HistoryViewModel.saveResult(peakSpeedKph: maxSpeed, for: userID)
            } catch {
                print("Error saving result: \(error.localizedDescription)")
            }
        }
        
        appState = .completed(maxSpeed)
    }

    func reset() {
        videoProcessor = nil
        cancellables.removeAll()
        appState = .idle
    }
}
