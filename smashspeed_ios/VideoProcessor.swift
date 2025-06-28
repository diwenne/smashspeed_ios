//
//  VideoProcessor.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import Foundation
import AVFoundation
import CoreImage

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

    func processVideo(progressHandler: @escaping (Progress) -> Void) async throws -> [FrameAnalysis] {
        let asset = AVURLAsset(url: videoURL)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let videoDuration = try await asset.load(.duration)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let assetReader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        assetReader.add(readerOutput)
        assetReader.startReading()
        
        var analysisResults: [FrameAnalysis] = []
        var frameCount = 0
        let totalFrames = Int(CMTimeGetSeconds(videoDuration) * Double(frameRate))
        let progress = Progress(totalUnitCount: Int64(totalFrames))
        
        print("--- Video Processing Started ---")

        while assetReader.status == .reading {
            if isCancelled { break }
            
            if let sampleBuffer = readerOutput.copyNextSampleBuffer(),
               let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                var detectedBox: CGRect? = nil
                var calculatedSpeed: Double? = nil
                
                do {
                    // --- THE FIX IS HERE ---
                    // This line correctly separates the returned tuple into two distinct variables.
                    let (box, confidence) = try modelHandler.performDetection(on: pixelBuffer)
                    
                    // Now we can use 'confidence' and 'box' separately.
                    if let conf = confidence {
                        print("Frame \(frameCount): Detected object with confidence \(String(format: "%.2f", conf))")
                    } else {
                        print("Frame \(frameCount): No object detected.")
                    }
                    
                    if let box = box {
                        detectedBox = box
                        let frameSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
                        
                        if let speedKPH = tracker.track(box: box, timestamp: timestamp, frameSize: frameSize, fps: frameRate) {
                            calculatedSpeed = speedKPH
                        }
                    }
                } catch {
                    print("Frame \(frameCount): Detection failed with error: \(error)")
                }
                
                let frameResult = FrameAnalysis(timestamp: timestamp, boundingBox: detectedBox, speedKPH: calculatedSpeed)
                analysisResults.append(frameResult)

                frameCount += 1
                progress.completedUnitCount = Int64(frameCount)
                
                await MainActor.run { progressHandler(progress) }
            }
        }
        
        print("--- Video Processing Finished ---")
        
        if assetReader.status == .failed {
            throw assetReader.error ?? NSError(domain: "VideoProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Asset reader failed"])
        }
        
        return analysisResults
    }
}
