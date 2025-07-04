//
//  AppModels.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//


// AppModels.swift
import Foundation
import CoreMedia
import CoreGraphics

// The result from the initial video processing.
struct VideoAnalysisResult {
    let frameData: [FrameAnalysis]
    let frameRate: Float
    let videoSize: CGSize
    let scaleFactor: Double
}

// Data for a single frame.
struct FrameAnalysis: Identifiable {
    let id = UUID()
    let timestamp: CMTime
    var boundingBox: CGRect?
    var speedKPH: Double?
    var trackedPoint: CGPoint?
}
