//
//  YOLOv5ModelHandler.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import Foundation
import Vision
import CoreImage
import UIKit

class YOLOv5ModelHandler {
    
    // MARK: - Prediction Struct
    
    /// A struct to hold the result of a single object detection.
    /// This must be public so VideoProcessor can access it.
    public struct Prediction {
        public let confidence: Float
        // This rect is in the model's coordinate space (e.g., 640x640 pixels)
        public let rect: CGRect
    }
    
    // MARK: - Properties
    
    private let model: VNCoreMLModel
    let modelInputSize = CGSize(width: 640, height: 640)
    private let confidenceThreshold: Float = 0.10
    private let iouThreshold: Float = 0.45
    
    // MARK: - Initialization
    
    init?() {
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let coreMLModel = try best(configuration: configuration).model
            self.model = try VNCoreMLModel(for: coreMLModel)
            #if DEBUG
            print("✅ YOLOv5ModelHandler: Model loaded successfully.")
            #endif
            
        } catch {
            #if DEBUG
            print("❌ YOLOv5ModelHandler: CRITICAL ERROR - Failed to load CoreML model: \(error)")
            #endif
            return nil
        }
    }
    
    // MARK: - Main Inference Function
    
    /// Performs detection and returns an array of all valid predictions.
    func performDetection(on pixelBuffer: CVPixelBuffer, completion: @escaping (Result<[Prediction], Error>) -> Void) {
        
        guard let resizedBuffer = try? ImageProcessor.resizePixelBuffer(pixelBuffer, to: modelInputSize) else {
            let error = NSError(domain: "YOLOv5ModelHandler", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to resize pixel buffer."])
            completion(.failure(error))
            return
        }
        
        let request = VNCoreMLRequest(model: model) { (request, error) in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let results = request.results,
                  let output = results.first as? VNCoreMLFeatureValueObservation,
                  let multiArray = output.featureValue.multiArrayValue else {
                completion(.success([])) // Return empty array if no results
                return
            }
            
            let predictions = self.decodeOutput(multiArray: multiArray)
            
            
            let nmsResults = self.nonMaxSuppression(predictions: predictions, iouThreshold: self.iouThreshold)
            
    
            // Return ALL detections after non-max suppression.
            completion(.success(nmsResults))
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: resizedBuffer, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Post-processing
    
    private func decodeOutput(multiArray: MLMultiArray) -> [Prediction] {
        var predictions: [Prediction] = []
        let pointer = UnsafeMutableBufferPointer<Float32>(start: multiArray.dataPointer.assumingMemoryBound(to: Float32.self),
                                                          count: multiArray.count)
        
        let numBoxes = multiArray.shape[1].intValue
        let numAttributes = multiArray.shape[2].intValue
        
        for i in 0..<numBoxes {
            let offset = i * numAttributes
            let x = pointer[offset]       // center_x
            let y = pointer[offset + 1]   // center_y
            let w = pointer[offset + 2]   // width
            let h = pointer[offset + 3]   // height
            
            let confidence = pointer[offset + 4]
            let classProbability = pointer[offset + 5] // Assuming single class
            let finalConfidence = confidence * classProbability

            if finalConfidence >= self.confidenceThreshold {
                let rect = CGRect(x: CGFloat(x - w / 2),
                                  y: CGFloat(y - h / 2),
                                  width: CGFloat(w),
                                  height: CGFloat(h))
                
                let prediction = Prediction(confidence: finalConfidence, rect: rect)
                predictions.append(prediction)
            }
        }
        return predictions
    }
    
    private func nonMaxSuppression(predictions: [Prediction], iouThreshold: Float) -> [Prediction] {
        let sortedPredictions = predictions.sorted { $0.confidence > $1.confidence }
        var selectedPredictions: [Prediction] = []
        var active = [Bool](repeating: true, count: sortedPredictions.count)

        for i in 0..<sortedPredictions.count {
            if active[i] {
                selectedPredictions.append(sortedPredictions[i])
                
                for j in (i + 1)..<sortedPredictions.count {
                    if active[j] {
                        let iou = calculateIOU(box1: sortedPredictions[i].rect, box2: sortedPredictions[j].rect)
                        if iou > iouThreshold {
                            active[j] = false
                        }
                    }
                }
            }
        }
        return selectedPredictions
    }

    private func calculateIOU(box1: CGRect, box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        let unionArea = (box1.width * box1.height) + (box2.width * box2.height) - (intersection.width * intersection.height)
        
        guard unionArea > 0 else { return 0 }
        
        let iou = (intersection.width * intersection.height) / unionArea
        return Float(iou)
    }
}
