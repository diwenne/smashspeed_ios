import Foundation
import CoreGraphics
import CoreMedia
import Vision

class ShuttlecockTracker {
    let scaleFactor: Double
    
    private var previousPoint: CGPoint?
    // Note: previousTimestamp is no longer used in the calculation but is kept for potential future use.
    private var previousTimestamp: CMTime?
    
    init(scaleFactor: Double) {
        self.scaleFactor = scaleFactor
    }
    
    /// Tracks the shuttlecock and returns both the calculated speed and the point used for tracking.
    /// - Returns: A tuple containing the speed in KPH (optional) and the tracking point (optional).
    func track(box: CGRect?, timestamp: CMTime, frameSize: CGSize, fps: Float) -> (speedKPH: Double?, point: CGPoint?) {
        guard let validBox = box else {
            // If there's no box on this frame, reset the previous point
            // to avoid calculating speed across a large gap of missed frames.
            previousPoint = nil
            return (nil, nil)
        }
        
        // Convert normalized box to pixel coordinates.
        let pixelBox = VNImageRectForNormalizedRect(validBox, Int(frameSize.width), Int(frameSize.height))
        
        // Determine the leading point ("tip") of the shuttlecock.
        let currentPoint = getTip(of: pixelBox, previousCenter: self.previousPoint)
        var speedKPH: Double? = nil

        // Calculate speed if there is a previous point to compare against.
        if let prevPoint = previousPoint {
            let dx = currentPoint.x - prevPoint.x
            let dy = currentPoint.y - prevPoint.y
            let pixelDistance = sqrt(dx * dx + dy * dy)
            
            // --- FIX: Calculate time difference based on FPS instead of timestamps ---
            // This provides a constant time interval and avoids corrupt timestamp issues.
            let timeDifference = 1.0 / Double(fps)
            
            // Ensure time difference is valid to prevent division by zero.
            if timeDifference > 0.0001 {
                let pixelsPerSecond = pixelDistance / timeDifference
                let metersPerSecond = pixelsPerSecond * self.scaleFactor
                #if DEBUG
                print("time difference: \(timeDifference)")
                #endif
                speedKPH = metersPerSecond * 3.6
            }
        }

        // Update state for the next frame.
        self.previousPoint = currentPoint
        self.previousTimestamp = timestamp
        
        // Return both the speed and the point used for this frame's calculation.
        return (speedKPH, currentPoint)
    }
    
    /// Determines the leading point of the bounding box based on its direction of movement.
    private func getTip(of box: CGRect, previousCenter: CGPoint?) -> CGPoint {
        let center = CGPoint(x: box.midX, y: box.midY)
        
        // If there's no previous point, default to the center of the current box.
        guard let prevCenter = previousCenter else {
            return center
        }
        
        let dx = center.x - prevCenter.x
        let dy = center.y - prevCenter.y
        
        // Choose the point on the leading edge of the box.
        if abs(dx) > abs(dy) {
            // Moving more horizontally
            return CGPoint(x: dx >= 0 ? box.maxX : box.minX, y: center.y)
        } else {
            // Moving more vertically
            return CGPoint(x: center.x, y: dy >= 0 ? box.maxY : box.minY)
        }
    }
}

