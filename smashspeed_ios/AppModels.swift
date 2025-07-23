//
//  AppModels.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//

import Foundation
import CoreMedia
import CoreGraphics
import FirebaseFirestore

// MARK: - Core Analysis Models

// The result from the initial video processing.
struct VideoAnalysisResult {
    let frameData: [FrameAnalysis]
    let frameRate: Float
    let videoSize: CGSize
    let scaleFactor: Double
}

// Data for a single frame during local analysis.
// Note: This model is NOT saved to Firestore.
struct FrameAnalysis: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Double // Using Double for easier conversion
    var boundingBox: CGRect? // ✅ CHANGED: This is now optional to handle frames with no detection.
    var speedKPH: Double?
    var trackedPoint: CGPoint?
}


// MARK: - Firestore Data Models (Codable for saving)

// A helper struct to make CGRect Codable for Firestore.
struct CodableRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    
    // Convenience initializer to convert from CGRect
    init(from rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.width
        self.height = rect.height
    }

    // Convenience method to convert back to CGRect
    func toCGRect() -> CGRect {
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// Represents the detailed data for a single analyzed frame that gets saved.
struct FrameData: Codable, Hashable {
    let timestamp: Double
    let speedKPH: Double
    let boundingBox: CodableRect
}

// The final result object that is saved to the 'detections' collection in Firestore.
struct DetectionResult: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let userID: String
    let date: Timestamp
    let peakSpeedKph: Double
    var videoURL: String?
    var frameData: [FrameData]?
    
    var formattedSpeed: String { String(format: "%.1f km/h", peakSpeedKph) }
}
