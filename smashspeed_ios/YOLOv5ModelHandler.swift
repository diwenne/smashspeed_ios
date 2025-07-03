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
    
    // MARK: - Properties
    
    private let model: VNCoreMLModel
    private let modelInputSize = CGSize(width: 640, height: 640)
    private let confidenceThreshold: Float = 0.25
    private let iouThreshold: Float = 0.45
    
    // MARK: - Initialization
    
    init?() {
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let coreMLModel = try best(configuration: configuration).model
            self.model = try VNCoreMLModel(for: coreMLModel)
            print("✅ YOLOv5ModelHandler: Model loaded successfully.")
            
        } catch {
            print("❌ YOLOv5ModelHandler: CRITICAL ERROR - Failed to load CoreML model: \(error)")
            return nil
        }
    }
    
    // MARK: - Main Inference Function
    
    func performDetection(on pixelBuffer: CVPixelBuffer, completion: @escaping (Result<(CGRect?, Float?), Error>) -> Void) {
        
        let originalSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        
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
                completion(.success((nil, nil)))
                return
            }
            
            let predictions = self.decodeOutput(multiArray: multiArray)
            let nmsResults = self.nonMaxSuppression(predictions: predictions, iouThreshold: self.iouThreshold)
            
            if let bestResult = nmsResults.max(by: { $0.confidence < $1.confidence }) {
                
                // `bestResult.rect` is a CGRect in the 640x640 (model input) pixel space.
                // We now convert it to the original video frame's pixel space.
                let pixelRect = self.scaleBoxFromModelToOriginal(bestResult.rect, modelSize: self.modelInputSize, originalSize: originalSize)
                
                // Finally, normalize the result for the rest of the app.
                let normalizedRect = CGRect(
                    x: pixelRect.origin.x / originalSize.width,
                    y: pixelRect.origin.y / originalSize.height,
                    width: pixelRect.size.width / originalSize.width,
                    height: pixelRect.size.height / originalSize.height
                )

                print("✅ HANDLER SENDING NORMALIZED RECT: \(normalizedRect)")
                completion(.success((normalizedRect, bestResult.confidence)))
                
            } else {
                completion(.success((nil, nil)))
            }
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
    
    private struct Prediction {
        let classIndex: Int
        let confidence: Float
        // This rect is in the model's coordinate space (e.g., 640x640 pixels)
        let rect: CGRect
    }

    private func decodeOutput(multiArray: MLMultiArray) -> [Prediction] {
        var predictions: [Prediction] = []
        let pointer = UnsafeMutableBufferPointer<Float32>(start: multiArray.dataPointer.assumingMemoryBound(to: Float32.self),
                                                          count: multiArray.count)
        
        let numBoxes = multiArray.shape[1].intValue
        let numAttributes = multiArray.shape[2].intValue
        
        for i in 0..<numBoxes {
            let offset = i * numAttributes
            // The box coordinates from the tensor are already scaled to the model input size (e.g., 640x640)
            let x = pointer[offset]     // center_x
            let y = pointer[offset + 1] // center_y
            let w = pointer[offset + 2] // width
            let h = pointer[offset + 3] // height
            
            let confidence = pointer[offset + 4]
            let classProbability = pointer[offset + 5] // Assuming single class at index 5
            let finalConfidence = confidence * classProbability

            if finalConfidence >= self.confidenceThreshold {
                let rect = CGRect(x: CGFloat(x - w / 2),
                                  y: CGFloat(y - h / 2),
                                  width: CGFloat(w),
                                  height: CGFloat(h))
                
                let prediction = Prediction(classIndex: 0, confidence: finalConfidence, rect: rect)
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
        let union = box1.union(box2)
        
        guard union.width > 0, union.height > 0 else { return 0 }
        
        let iou = (intersection.width * intersection.height) / (union.width * union.height)
        return Float(iou)
    }
    
    // --- CORRECTED SCALING LOGIC ---
    /// Converts a bounding box from the model's pixel space (e.g., 640x640) back to the original image's pixel space.
    private func scaleBoxFromModelToOriginal(_ boxInModelCoords: CGRect, modelSize: CGSize, originalSize: CGSize) -> CGRect {
        // 1. Calculate the scale factor and padding used for letterboxing
        let scale = min(modelSize.width / originalSize.width, modelSize.height / originalSize.height)
        let offsetX = (modelSize.width - originalSize.width * scale) / 2
        let offsetY = (modelSize.height - originalSize.height * scale) / 2
        
        // 2. Remove the padding from the box's coordinates
        let unpaddedX = boxInModelCoords.origin.x - offsetX
        let unpaddedY = boxInModelCoords.origin.y - offsetY
        
        // 3. Scale the coordinates back up to the original image size
        let finalX = unpaddedX / scale
        let finalY = unpaddedY / scale
        let finalWidth = boxInModelCoords.width / scale
        let finalHeight = boxInModelCoords.height / scale
        
        return CGRect(x: finalX, y: finalY, width: finalWidth, height: finalHeight)
    }
}
