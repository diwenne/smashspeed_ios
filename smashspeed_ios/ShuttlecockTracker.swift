//
//  ShuttlecockTracker.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//


//
//  ShuttlecockTracker.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import Vision
import Foundation
import CoreGraphics
import CoreMedia

class ShuttlecockTracker {
    // Configuration
    private let scaleFactor: Double // m/pixel
    
    // State
    private var previousPoint: CGPoint?
    private var previousTimestamp: CMTime?
    
    init(scaleFactor: Double) {
        self.scaleFactor = scaleFactor
    }
    
    /// Tracks the object and returns the calculated speed in km/h.
    func track(box: CGRect, timestamp: CMTime, frameSize: CGSize, fps: Float) -> Double? {
        // The box from Vision is normalized (0.0 to 1.0). Convert to pixel coordinates.
        let pixelBox = VNImageRectForNormalizedRect(box, Int(frameSize.width), Int(frameSize.height))
        
        let currentPoint = getTip(of: pixelBox, previousCenter: self.previousPoint)
        var speedKPH: Double? = nil

        if let prevPoint = previousPoint, let prevTimestamp = previousTimestamp {
            let dx = currentPoint.x - prevPoint.x
            let dy = currentPoint.y - prevPoint.y
            let pixelDistance = sqrt(dx * dx + dy * dy)
            
            let timeDifference = CMTimeGetSeconds(timestamp - prevTimestamp)
            
            // Avoid division by zero if timestamps are identical
            if timeDifference > 1e-6 {
                let pixelsPerSecond = pixelDistance / timeDifference
                let metersPerSecond = pixelsPerSecond * scaleFactor
                speedKPH = metersPerSecond * 3.6 // Convert m/s to km/h
            }
        }

        self.previousPoint = currentPoint
        self.previousTimestamp = timestamp
        
        return speedKPH
    }
    
    /// Replicates the 'tip' logic from the Python script to find the leading edge of the bounding box.
    private func getTip(of box: CGRect, previousCenter: CGPoint?) -> CGPoint {
        let center = CGPoint(x: box.midX, y: box.midY)
        
        guard let prevCenter = previousCenter else {
            // If no previous point, just use the center
            return center
        }
        
        let dx = center.x - prevCenter.x
        let dy = center.y - prevCenter.y
        
        if abs(dx) > abs(dy) {
            // Horizontal movement is dominant
            return CGPoint(x: dx >= 0 ? box.maxX : box.minX, y: center.y)
        } else {
            // Vertical movement is dominant
            return CGPoint(x: center.x, y: dy >= 0 ? box.maxY : box.minY)
        }
    }
}
