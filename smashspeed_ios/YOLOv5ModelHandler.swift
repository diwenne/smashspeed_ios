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
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            
            // NOTE: Remember to change 'yolov5s' back to 'best' when you use your own model
            let coreMLModel = try yolov5s(configuration: configuration).model
            
            self.model = try VNCoreMLModel(for: coreMLModel)
            print("✅ YOLOv5ModelHandler: Model loaded successfully using CPU only.")
        } catch {
            print("❌ YOLOv5ModelHandler: CRITICAL ERROR - Failed to load CoreML model: \(error)")
            return nil
        }
    }
    
    /// Performs detection and returns the result via a completion handler.
    /// This is an asynchronous operation.
    func performDetection(on pixelBuffer: CVPixelBuffer, completion: @escaping (Result<(CGRect?, Float?), Error>) -> Void) {
        
        let request = VNCoreMLRequest(model: model) { request, error in
            // This completion block runs after the model has finished.
            
            // Check for a top-level error from the request itself
            if let error = error {
                print("❌ Vision request failed with error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            // Make sure we have results and they are of the correct type
            guard let results = request.results as? [VNRecognizedObjectObservation] else {
                print("ℹ️ Model did not return any VNRecognizedObjectObservation results.")
                // This is not a failure, it's a valid result (0 objects found).
                completion(.success((nil, nil)))
                return
            }

            let confidenceThreshold: Float = 0.25
            let confidentResults = results.filter { $0.confidence >= confidenceThreshold }

            // Find the best result among the confident ones
            if let bestResult = confidentResults.max(by: { $0.confidence < $1.confidence }) {
                // Success case with a prediction
                completion(.success((bestResult.boundingBox, bestResult.confidence)))
            } else {
                // Success case with no predictions above the threshold
                completion(.success((nil, nil)))
            }
        }

        request.imageCropAndScaleOption = .scaleFill

        // We still use a handler to perform the request
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Perform the request on a background thread
                try handler.perform([request])
            } catch {
                // If the handler itself throws an error, pass it to the completion handler
                print("❌ Image request handler failed with error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
}
