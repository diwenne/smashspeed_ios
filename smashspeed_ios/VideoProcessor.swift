//
//  VideoProcessor.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import Foundation
import AVFoundation
import CoreImage
import Vision

//struct VideoAnalysisResult {
//    let frameData: [FrameAnalysis]
//    let frameRate: Float
//    let videoSize: CGSize
//    let scaleFactor: Double
//}

class VideoProcessor {
    let videoURL: URL
    let modelHandler: YOLOv5ModelHandler
    let tracker: ShuttlecockTracker

    private var isCancelled = false
    
    init(videoURL: URL, modelHandler: YOLOv5ModelHandler, tracker: ShuttlecockTracker) {
        self.videoURL = videoURL
        self.modelHandler = modelHandler
        self.tracker = tracker
    }
    
    func cancelProcessing() {
        isCancelled = true
    }

    func processVideo(progressHandler: @escaping (Progress) -> Void) async throws -> VideoAnalysisResult? {
        let asset = AVURLAsset(url: videoURL)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        
        let videoDuration = try await asset.load(.duration)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let videoSize = try await videoTrack.load(.naturalSize)
        
        let assetReader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        assetReader.add(readerOutput)
        assetReader.startReading()
        
        var analysisResults: [FrameAnalysis] = []
        var frameCount = 0
        let totalFrames = Int(CMTimeGetSeconds(videoDuration) * Double(frameRate))
        let progress = Progress(totalUnitCount: Int64(totalFrames))
        
        while assetReader.status == .reading {
            if isCancelled { break }
            
            if let sampleBuffer = readerOutput.copyNextSampleBuffer(),
               let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                
                // Perform object detection on the current frame's pixel buffer.
                let (box, _) = await withCheckedContinuation { continuation in
                    modelHandler.performDetection(on: pixelBuffer) { result in
                        switch result {
                        case .success(let detectionResult): continuation.resume(returning: detectionResult)
                        case .failure: continuation.resume(returning: (nil, nil))
                        }
                    }
                }
                
                // --- MODIFIED SECTION ---
                // Always call the tracker, passing the optional box. The tracker handles the nil case.
                let trackingResult = tracker.track(
                    box: box,
                    timestamp: timestamp,
                    frameSize: videoSize,
                    fps: frameRate
                )
                
                // Create the FrameAnalysis struct with all the results.
                let frameResult = FrameAnalysis(
                    timestamp: timestamp,
                    boundingBox: box, // The box from the model
                    speedKPH: trackingResult.speedKPH,
                    trackedPoint: trackingResult.point
                )
                analysisResults.append(frameResult)
                // --- END MODIFIED SECTION ---

                frameCount += 1
                progress.completedUnitCount = Int64(frameCount)
                
                await MainActor.run { progressHandler(progress) }
            }
        }
        
        if assetReader.status == .failed { throw assetReader.error ?? NSError() }
        
        return VideoAnalysisResult(frameData: analysisResults, frameRate: frameRate, videoSize: videoSize, scaleFactor: tracker.scaleFactor)
    }
}

