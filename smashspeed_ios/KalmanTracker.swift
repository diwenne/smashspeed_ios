//
//  KalmanTracker.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import Foundation
import CoreGraphics

class KalmanTracker {

    // MARK: - Properties
    let scaleFactor: Double

    // MARK: - Kalman State Variables
    private var x: (Double, Double, Double, Double) = (0, 0, 0, 0)
    private var p: ((Double, Double, Double, Double),
                    (Double, Double, Double, Double),
                    (Double, Double, Double, Double),
                    (Double, Double, Double, Double)) = ( (1, 0, 0, 0),
                                                           (0, 1, 0, 0),
                                                           (0, 0, 1000, 0),
                                                           (0, 0, 0, 1000) )
    private let q: Double = 1e-4
    private let r: Double = 0.01
    private var isInitialized = false

    // MARK: - Initialization
    init(scaleFactor: Double) {
        self.scaleFactor = scaleFactor
    }

    // MARK: - Public Methods

    /// Predicts the next state and returns the predicted point.
    /// Returns nil if the tracker is not yet initialized.
    func predict(dt: Double = 1.0) -> CGPoint? {
        guard isInitialized else { return nil }

        // State Transition Model F
        let f11 = x.0 + dt * x.2
        let f12 = x.1 + dt * x.3
        x = (f11, f12, x.2, x.3)

        // Update State Covariance
        let p00 = p.0.0 + dt * (p.2.0 + p.0.2) + dt * dt * p.2.2 + q
        let p01 = p.0.1 + dt * (p.2.1 + p.0.3) + dt * dt * p.2.3
        let p02 = p.0.2 + dt * p.2.2
        let p03 = p.0.3 + dt * p.2.3
        let p10 = p.1.0 + dt * (p.3.0 + p.1.2) + dt * dt * p.3.2
        let p11 = p.1.1 + dt * (p.3.1 + p.1.3) + dt * dt * p.3.3 + q
        let p12 = p.1.2 + dt * p.3.2
        let p13 = p.1.3 + dt * p.3.3
        let p20 = p.2.0 + dt * p.2.2
        let p21 = p.2.1 + dt * p.2.3
        let p22 = p.2.2 + q
        let p23 = p.2.3
        let p30 = p.3.0 + dt * p.3.2
        let p31 = p.3.1 + dt * p.3.3
        let p32 = p.3.2
        let p33 = p.3.3 + q
        p = ((p00, p01, p02, p03), (p10, p11, p12, p13), (p20, p21, p22, p23), (p30, p31, p32, p33))
        
        return CGPoint(x: x.0, y: x.1)
    }

    /// Updates the filter's state with a new measurement.
    func update(measurement: CGPoint) {
        if !isInitialized {
            x = (measurement.x, measurement.y, 0, 0)
            isInitialized = true
            return
        }

        let s1 = p.0.0 + r
        let s2 = p.1.1 + r
        let detS = s1 * s2 - p.1.0 * p.0.1
        let invS = (s2 / detS, -p.0.1 / detS, -p.1.0 / detS, s1 / detS)
        let k11 = p.0.0 * invS.0 + p.0.1 * invS.2
        let k12 = p.0.0 * invS.1 + p.0.1 * invS.3
        let k21 = p.1.0 * invS.0 + p.1.1 * invS.2
        let k22 = p.1.0 * invS.1 + p.1.1 * invS.3
        let k31 = p.2.0 * invS.0 + p.2.1 * invS.2
        let k32 = p.2.0 * invS.1 + p.2.1 * invS.3
        let k41 = p.3.0 * invS.0 + p.3.1 * invS.2
        let k42 = p.3.0 * invS.1 + p.3.1 * invS.3

        let y1 = measurement.x - x.0
        let y2 = measurement.y - x.1
        x.0 += k11 * y1 + k12 * y2
        x.1 += k21 * y1 + k22 * y2
        x.2 += k31 * y1 + k32 * y2
        x.3 += k41 * y1 + k42 * y2

        let i_kh_11 = 1.0 - k11
        let i_kh_12 = -k12
        let i_kh_21 = -k21
        let i_kh_22 = 1.0 - k22
        let p00 = p.0.0 * i_kh_11 + p.1.0 * i_kh_12
        let p01 = p.0.1 * i_kh_11 + p.1.1 * i_kh_12
        let p02 = p.0.2 * i_kh_11 + p.1.2 * i_kh_12
        let p03 = p.0.3 * i_kh_11 + p.1.3 * i_kh_12
        let p10 = p.0.0 * i_kh_21 + p.1.0 * i_kh_22
        let p11 = p.0.1 * i_kh_21 + p.1.1 * i_kh_22
        let p12 = p.0.2 * i_kh_21 + p.1.2 * i_kh_22
        let p13 = p.0.3 * i_kh_21 + p.1.3 * i_kh_22
        p.0 = (p00, p01, p02, p03)
        p.1 = (p10, p11, p12, p13)
    }

    /// Returns the current estimated state (position, velocity vector, and speed magnitude).
    /// The returned speed is the raw velocity in pixels/frame.
    func getCurrentState() -> (point: CGPoint, velocity: CGPoint, speed: Double?) {
        guard isInitialized else { return (CGPoint.zero, CGPoint.zero, nil) }
        let point = CGPoint(x: x.0, y: x.1)
        let velocity = CGPoint(x: x.2, y: x.3)
        let speedPixelsPerFrame = sqrt(x.2 * x.2 + x.3 * x.3)
        return (point, velocity, speedPixelsPerFrame)
    }
    
    /// Creates a deep copy of the tracker's current state.
    func copy() -> KalmanTracker {
        let newTracker = KalmanTracker(scaleFactor: self.scaleFactor)
        newTracker.x = self.x
        newTracker.p = self.p
        newTracker.isInitialized = self.isInitialized
        return newTracker
    }
    
    func reset() {
        isInitialized = false
        p = ( (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1000, 0), (0, 0, 0, 1000) )
    }
}
