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

    func processVideo(progressHandler: ((Progress) -> Void)?) async throws -> VideoAnalysisResult? {
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
            
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                // When the reader is finished, this will be nil. Break the loop.
                break
            }
            
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            // Perform object detection on the current frame's pixel buffer.
            let (box, _) = await withCheckedContinuation { continuation in
                modelHandler.performDetection(on: pixelBuffer) { result in
                    switch result {
                    case .success(let detectionResult): continuation.resume(returning: detectionResult)
                    case .failure: continuation.resume(returning: (nil, nil))
                    }
                }
            }
            
            // --- CHANGED ---
            // The guard statement that skipped frames has been removed.
            // The logic below now runs for EVERY frame.
            
            // Pass the (optional) box to the tracker.
            // The tracker is already designed to handle a nil box.
            let trackingResult = tracker.track(
                box: box, // Pass the optional box directly
                timestamp: presentationTime,
                frameSize: videoSize,
                fps: frameRate
            )
            
            // Create the FrameAnalysis struct for every frame.
            // The `boundingBox` will be nil if nothing was detected.
            let frameResult = FrameAnalysis(
                timestamp: presentationTime.seconds,
                boundingBox: box, // Use the optional box
                speedKPH: trackingResult.speedKPH,
                trackedPoint: trackingResult.point
            )
            analysisResults.append(frameResult)
            
            // Update progress
            frameCount += 1
            progress.completedUnitCount = Int64(frameCount)
            
            if let handler = progressHandler {
                await MainActor.run { handler(progress) }
            }
        }
        
        if assetReader.status == .failed { throw assetReader.error ?? NSError() }
        
        return VideoAnalysisResult(frameData: analysisResults, frameRate: frameRate, videoSize: videoSize, scaleFactor: tracker.scaleFactor)
    }
}
