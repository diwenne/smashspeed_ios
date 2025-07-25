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
        
        let maxSpeedKPH: Double = 550.0 // Plausible speed limit
        
        while assetReader.status == .reading {
            if isCancelled { break }
            
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                break
            }
            
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            
            // --- ❗️ LOGIC CHANGE ---
            // 1. Predict where the tracker thinks the shuttlecock will be.
            //    This now returns an optional CGPoint, which will be nil on frame 1.
            let predictedPoint = tracker.predict(dt: 1.0)
            
            #if DEBUG
            if let point = predictedPoint, videoSize.width > 0, videoSize.height > 0 {
                let normalizedX = point.x / videoSize.width
                let normalizedY = point.y / videoSize.height
                print(String(format: "🔮 Frame %d Kalman PREDICTED (norm): [x: %.3f, y: %.3f]", frameCount + 1, normalizedX, normalizedY))
            }
            #endif
            
            // 2. Get ALL candidate detections from the model.
            let allDetections: [YOLOv5ModelHandler.Prediction] = await withCheckedContinuation { continuation in
                modelHandler.performDetection(on: pixelBuffer) { result in
                    switch result {
                    case .success(let detections): continuation.resume(returning: detections)
                    case .failure: continuation.resume(returning: [])
                    }
                }
            }

            // 3. Score detections based on confidence and proximity to prediction.
            var bestDetection: (prediction: YOLOv5ModelHandler.Prediction, score: Double)? = nil
            if !allDetections.isEmpty {
                let scoredDetections = allDetections.map { detection -> (prediction: YOLOv5ModelHandler.Prediction, score: Double) in
                    let pixelRect = scaleBoxFromModelToOriginal(detection.rect, modelSize: modelHandler.modelInputSize, originalSize: videoSize)
                    // The 'predictedPoint' is now correctly nil on the first frame.
                    let score = calculateScore(for: pixelRect.center, confidence: Double(detection.confidence), predictedPoint: predictedPoint, frameSize: videoSize)
                    return (detection, score)
                }

                #if DEBUG
                if scoredDetections.count >= 1 {
                    print("⚖️ Frame \(frameCount + 1) Scoring \(scoredDetections.count) Detections:")
                    for item in scoredDetections {
                        let scaledRect = scaleBoxFromModelToOriginal(item.prediction.rect, modelSize: modelHandler.modelInputSize, originalSize: videoSize)
                        let normX = scaledRect.origin.x / videoSize.width
                        let normY = scaledRect.origin.y / videoSize.height
                        print(String(format: "   - Box (norm): [x: %.3f, y: %.3f], Conf: %.2f, Score: %.3f", normX, normY, item.prediction.confidence, item.score))
                    }
                }
                #endif

                bestDetection = scoredDetections.max(by: { $0.score < $1.score })
            }
            
            // 4. Update the tracker with the best detection, if one was found.
            var finalBox: CGRect?
            var finalSpeed: Double?
            var finalPoint: CGPoint?
            
            if let chosenOne = bestDetection {
                let pixelRect = scaleBoxFromModelToOriginal(chosenOne.prediction.rect, modelSize: modelHandler.modelInputSize, originalSize: videoSize)
                
                tracker.update(measurement: pixelRect.center)
                
                finalBox = CGRect(x: pixelRect.origin.x / videoSize.width,
                                  y: pixelRect.origin.y / videoSize.height,
                                  width: pixelRect.size.width / videoSize.width,
                                  height: pixelRect.size.height / videoSize.height)
                
                #if DEBUG
                if let box = finalBox, allDetections.count >= 1 {
                    print(String(format: "✅ Frame %d CHOSEN Box (norm): [x: %.3f, y: %.3f], Score: %.3f", frameCount + 1, box.origin.x, box.origin.y, chosenOne.score))
                }
                #endif
            }
            
            // 5. Get the final state (position and speed) from the tracker.
            let currentState = tracker.getCurrentState()
            let pixelsPerFrameVelocity = currentState.speedKPH ?? 0.0
            
            let pixelsPerSecond = pixelsPerFrameVelocity * Double(frameRate)
            let metersPerSecond = pixelsPerSecond * tracker.scaleFactor
            finalSpeed = metersPerSecond * 3.6
            
            if let speed = finalSpeed, speed > maxSpeedKPH {
                finalSpeed = nil
                tracker.reset()
            }
            
            finalPoint = currentState.point

            let frameResult = FrameAnalysis(
                timestamp: presentationTime.seconds,
                boundingBox: finalBox,
                speedKPH: finalSpeed,
                trackedPoint: finalPoint
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
        if let prediction = predictedPoint {
            let normalizer = frameSize.width / 4.0
            let distance = point.distance(to: prediction)
            distanceScore = max(0.0, 1.0 - (distance / normalizer))
        }
        
        return (confidenceWeight * confidence) + (distanceWeight * distanceScore)
    }

    private func scaleBoxFromModelToOriginal(_ boxInModelCoords: CGRect, modelSize: CGSize, originalSize: CGSize) -> CGRect {
        let scale = min(modelSize.width / originalSize.width, modelSize.height / originalSize.height)
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
