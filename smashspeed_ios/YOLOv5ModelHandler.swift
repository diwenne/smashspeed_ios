//
//  YOLOv5ModelHandler.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import Foundation
import Vision
import CoreImage

class YOLOv5ModelHandler {
    private let model: VNCoreMLModel
    
    init?() {
        do {
            // 1. Create a model configuration object
            let configuration = MLModelConfiguration()
            
            // 2. Tell the model to use ONLY the CPU (This is the critical line for the simulator)
            configuration.computeUnits = .cpuOnly
            
            // 3. Load the model using this new configuration
            let coreMLModel = try best(configuration: configuration).model
            
            self.model = try VNCoreMLModel(for: coreMLModel)
            
            // The print statement now confirms it's using the CPU
            print("✅ YOLOv5ModelHandler: Model 'best.mlpackage' loaded successfully using CPU only.")
            
        } catch {
            print("❌ YOLOv5ModelHandler: CRITICAL ERROR - Failed to load CoreML model: \(error)")
            return nil
        }
    }
    
    func performDetection(on pixelBuffer: CVPixelBuffer) throws -> (CGRect?, Float?) {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])
        
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return (nil, nil)
        }
        
        
        // 1. Define our confidence threshold. 0.25 is a good starting point.
        let confidenceThreshold: Float = 0.25
        
        // 2. Filter the results to keep only the ones with confidence >= our threshold.
        let confidentResults = results.filter { $0.confidence >= confidenceThreshold }
        
        // 3. From those confident results, find the one with the highest confidence.
        if let bestResult = confidentResults.max(by: { $0.confidence < $1.confidence }) {
            
            
            // Return both the box and its confidence score
            return (bestResult.boundingBox, bestResult.confidence)
        } else {
            // If there are no results with sufficient confidence, return nil.
            return (nil, nil)
        }
    }
}
