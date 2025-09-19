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
    let tracker: KalmanTracker

    private var isCancelled = false
    
    init(videoURL: URL, modelHandler: YOLOv5ModelHandler, tracker: KalmanTracker) {
        self.videoURL = videoURL
        self.modelHandler = modelHandler
        self.tracker = tracker
    }
    
    func cancelProcessing() {
        isCancelled = true
    }

    func processVideo(progressHandler: ((Progress) -> Void)?) async throws -> VideoAnalysisResult? {
        tracker.reset()
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
                break
            }
            
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            let predictedPoint = tracker.predict(dt: 1.0)
            
            let allDetections: [YOLOv5ModelHandler.Prediction] = await withCheckedContinuation { continuation in
                modelHandler.performDetection(on: pixelBuffer) { result in
                    switch result {
                    case .success(let detections): continuation.resume(returning: detections)
                    case .failure: continuation.resume(returning: [])
                    }
                }
            }

            var chosenDetection: YOLOv5ModelHandler.Prediction? = nil
            if !allDetections.isEmpty {
                let scoredDetections = allDetections.map { detection -> (prediction: YOLOv5ModelHandler.Prediction, score: Double) in
                    let pixelRect = scaleBoxFromModelToOriginal(detection.rect, modelSize: modelHandler.modelInputSize, originalSize: videoSize)
                    let score = calculateScore(for: pixelRect.center, confidence: Double(detection.confidence), predictedPoint: predictedPoint, frameSize: videoSize)
                    return (detection, score)
                }
                .sorted { $0.score > $1.score }

                if !tracker.isInitialized {
                    // Seed the tracker with the best detection, no speed check.
                    if let bestDetection = scoredDetections.first {
                        chosenDetection = bestDetection.prediction
                    }
                } else {
                    // Tracker is running, so apply speed filter.
                    let maxSpeedKPH: Double = 500.0
                    for scoredDetection in scoredDetections {
                        let tempTracker = tracker.copy()
                        let pixelRect = scaleBoxFromModelToOriginal(scoredDetection.prediction.rect, modelSize: modelHandler.modelInputSize, originalSize: videoSize)
                        tempTracker.update(measurement: pixelRect.center)
                        
                        if let tempState = tempTracker.getCurrentState() {
                            let pixelsPerFrameVelocity = tempState.speed ?? 0.0
                            let pixelsPerSecond = pixelsPerFrameVelocity * Double(frameRate)
                            let metersPerSecond = pixelsPerSecond * tempTracker.scaleFactor
                            let potentialSpeedKPH = metersPerSecond * 3.6

                            if potentialSpeedKPH < maxSpeedKPH {
                                chosenDetection = scoredDetection.prediction
                                break
                            }
                        }
                    }
                }
            }
            
            // Check the state *before* updating the tracker for this frame.
            let wasInitializedBeforeUpdate = tracker.isInitialized

            var finalBox: CGRect?
            if let chosenOne = chosenDetection {
                let pixelRect = scaleBoxFromModelToOriginal(chosenOne.rect, modelSize: modelHandler.modelInputSize, originalSize: videoSize)
                tracker.update(measurement: pixelRect.center) // Now update the tracker
                finalBox = CGRect(x: pixelRect.origin.x / videoSize.width,
                                  y: pixelRect.origin.y / videoSize.height,
                                  width: pixelRect.size.width / videoSize.width,
                                  height: pixelRect.size.height / videoSize.height)
            }

            var finalSpeedKPH: Double = 0.0
            var finalTrackedPoint: CGPoint? = nil

            // Get the state of the tracker *after* the potential update.
            if let currentState = tracker.getCurrentState() {
                finalTrackedPoint = currentState.point
                
                // Only calculate speed if the tracker was already running before this frame.
                if wasInitializedBeforeUpdate {
                    let pixelsPerFrameVelocity = currentState.speed ?? 0.0
                    let pixelsPerSecond = pixelsPerFrameVelocity * Double(frameRate)
                    let metersPerSecond = pixelsPerSecond * tracker.scaleFactor
                    finalSpeedKPH = metersPerSecond * 3.6
                }
            }

            let frameResult = FrameAnalysis(
                timestamp: presentationTime.seconds,
                boundingBox: finalBox,
                speedKPH: finalSpeedKPH,
                trackedPoint: finalTrackedPoint
            )
            analysisResults.append(frameResult)
            
            frameCount += 1
            progress.completedUnitCount = Int64(frameCount)
            if let handler = progressHandler {
                await MainActor.run { handler(progress) }
            }
        }
        
        if assetReader.status == .failed { throw assetReader.error ?? NSError() }
        
        return VideoAnalysisResult(frameData: analysisResults, frameRate: frameRate, videoSize: videoSize, scaleFactor: tracker.scaleFactor)
    }
    
    // MARK: - Helper Functions

    private func calculateScore(for point: CGPoint, confidence: Double, predictedPoint: CGPoint?, frameSize: CGSize) -> Double {
        let confidenceWeight = 0.3
        let distanceWeight = 0.7
        
        var distanceScore = 0.5
        if let prediction = predictedPoint, prediction != .zero {
            let normalizer = frameSize.width / 4.0
            let distance = point.distance(to: prediction)
            distanceScore = max(0.0, 1.0 - (distance / normalizer))
        }
        
        return (confidenceWeight * confidence) + (distanceWeight * distanceScore)
    }

    private func scaleBoxFromModelToOriginal(_ boxInModelCoords: CGRect, modelSize: CGSize, originalSize: CGSize) -> CGRect {
        let scaleX = modelSize.width / originalSize.width
        let scaleY = modelSize.height / originalSize.height
        let scale = min(scaleX, scaleY)
        
        let offsetX = (modelSize.width - originalSize.width * scale) / 2
        let offsetY = (modelSize.height - originalSize.height * scale) / 2
        
        let unpaddedX = boxInModelCoords.origin.x - offsetX
        let unpaddedY = boxInModelCoords.origin.y - offsetY
        
        let finalX = unpaddedX / scale
        let finalY = unpaddedY / scale
        let finalWidth = boxInModelCoords.width / scale
        let finalHeight = boxInModelCoords.height / scale
        
        return CGRect(x: finalX, y: finalY, width: finalWidth, height: finalHeight)
    }
}

// MARK: - Helper Extensions

extension CGPoint {
    func distance(to point: CGPoint) -> Double {
        return sqrt(pow(self.x - point.x, 2) + pow(self.y - point.y, 2))
    }
}

extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}
