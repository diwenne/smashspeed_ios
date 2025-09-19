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
            
            // 1. Predict where the tracker thinks the shuttlecock will be.
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

            var chosenDetection: (prediction: YOLOv5ModelHandler.Prediction, score: Double)? = nil
            
            if !allDetections.isEmpty {
                let scoredDetections = allDetections.map { detection -> (prediction: YOLOv5ModelHandler.Prediction, score: Double) in
                    let pixelRect = scaleBoxFromModelToOriginal(detection.rect, modelSize: modelHandler.modelInputSize, originalSize: videoSize)
                    let score = calculateScore(for: pixelRect.center, confidence: Double(detection.confidence), predictedPoint: predictedPoint, frameSize: videoSize)
                    return (detection, score)
                }
                .sorted { $0.score > $1.score } // Sort by score, highest first

                #if DEBUG
                if !scoredDetections.isEmpty {
                    print("⚖️ Frame \(frameCount + 1) Checking \(scoredDetections.count) Detections (sorted by score):")
                }
                #endif

                // --- GEMINI'S NOTE: This is the new logic block to fix the first-frame speed jump. ---
                // It checks if the tracker has been initialized yet.
                let mainTrackerState = tracker.getCurrentState()
                let trackerHasBeenInitialized = mainTrackerState.point != .zero
                
                if !trackerHasBeenInitialized {
                    // --- GEMINI'S NOTE: If the tracker is new, we 'seed' it with the best detection ---
                    // and skip all speed checks for this one frame to give it a starting point.
                    chosenDetection = scoredDetections.first
                    #if DEBUG
                    if chosenDetection != nil {
                        print("   - ✅ Tracker not initialized. Seeding with highest-scoring box.")
                    }
                    #endif
                } else {
                    // --- GEMINI'S NOTE: If the tracker is already moving, we enforce your original speed checks. ---
                    let maxSpeedKPH: Double = 450.0 // Increased for safety
                    let minSpeedKPH: Double = 5.0
                    let trackerHasEstablishedMotion = (mainTrackerState.speed ?? 0.0) > 0.0

                    for scoredDetection in scoredDetections {
                        let tempTracker = tracker.copy()
                        let pixelRect = scaleBoxFromModelToOriginal(scoredDetection.prediction.rect, modelSize: modelHandler.modelInputSize, originalSize: videoSize)
                        tempTracker.update(measurement: pixelRect.center)
                        let tempState = tempTracker.getCurrentState()
                        
                        let pixelsPerFrameVelocity = tempState.speed ?? 0.0
                        let pixelsPerSecond = pixelsPerFrameVelocity * Double(frameRate)
                        let metersPerSecond = pixelsPerSecond * tempTracker.scaleFactor
                        let potentialSpeedKPH = metersPerSecond * 3.6
                        
                        #if DEBUG
                        print(String(format: "   - 𝗧𝗲𝘀𝘁𝗶𝗻𝗴 box with score %.3f... potential speed: %.1f kph", scoredDetection.score, potentialSpeedKPH))
                        #endif

                        let isTooFast = potentialSpeedKPH >= maxSpeedKPH
                        let isTooSlow = potentialSpeedKPH < minSpeedKPH
                        let motionCheckFailed = isTooSlow && trackerHasEstablishedMotion

                        if !isTooFast && !motionCheckFailed {
                            chosenDetection = scoredDetection
                            #if DEBUG
                            print("   - ✅ PASSED speed check. Selecting this box.")
                            #endif
                            break
                        } else {
                            #if DEBUG
                            if isTooFast {
                                print(String(format: "   - ❌ REJECTED. Speed %.1f kph is too high (max: %.0f).", potentialSpeedKPH, maxSpeedKPH))
                            } else if motionCheckFailed {
                                print(String(format: "   - ❌ REJECTED. Speed %.1f kph is too low (min: %.0f).", potentialSpeedKPH, minSpeedKPH))
                            }
                            #endif
                        }
                    }
                }
            }
            
            // --- GEMINI'S NOTE: This new logic block correctly calculates the final speed. ---
            // 1. We check the tracker's state BEFORE we update it for the current frame.
            let wasInitializedBeforeUpdate = tracker.getCurrentState().point != .zero

            var finalBox: CGRect?
            if let chosenOne = chosenDetection {
                let pixelRect = scaleBoxFromModelToOriginal(chosenOne.prediction.rect, modelSize: modelHandler.modelInputSize, originalSize: videoSize)
                tracker.update(measurement: pixelRect.center)
                finalBox = CGRect(x: pixelRect.origin.x / videoSize.width,
                                  y: pixelRect.origin.y / videoSize.height,
                                  width: pixelRect.size.width / videoSize.width,
                                  height: pixelRect.size.height / videoSize.height)
            
                #if DEBUG
                print(String(format: "✅ Frame %d CHOSEN Box (norm): [x: %.3f, y: %.3f], Score: %.3f", frameCount + 1, finalBox!.origin.x, finalBox!.origin.y, chosenOne.score))
                #endif
            } else {
                #if DEBUG
                if !allDetections.isEmpty {
                    print("🔴 Frame \(frameCount + 1): All detections resulted in out-of-range speed. Using prediction only.")
                } else if frameCount > 0 {
                    print("📪 Frame \(frameCount + 1): No detections found. Using prediction only.")
                }
                #endif
            }

            // 2. We get the tracker's new state AFTER the potential update.
            let currentState = tracker.getCurrentState()
            
            // 3. The speed is ONLY calculated if the tracker was ALREADY initialized before this frame.
            //    This ensures the frame with the very first detection has a speed of 0.
            let pixelsPerFrameVelocity = wasInitializedBeforeUpdate ? (currentState.speed ?? 0.0) : 0.0

            let pixelsPerSecond = pixelsPerFrameVelocity * Double(frameRate)
            let metersPerSecond = pixelsPerSecond * tracker.scaleFactor
            let finalSpeed = metersPerSecond * 3.6
            let finalPoint = currentState.point

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
