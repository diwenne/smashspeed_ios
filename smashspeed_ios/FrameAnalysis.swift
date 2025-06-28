//
//  FrameAnaylsis.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//


import Foundation
import CoreGraphics
import CoreMedia

// This struct holds all the important data we capture for a single frame.
struct FrameAnalysis: Identifiable {
    let id = UUID()
    let timestamp: CMTime
    var boundingBox: CGRect?
    var speedKPH: Double?
}
