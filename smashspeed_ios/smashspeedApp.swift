//
//  smashspeedApp.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.


import SwiftUI

@main
struct smashspeedApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//import SwiftUI
//import Vision
//import UIKit
//import Foundation
//
//@main
//struct smashspeedApp: App {
//    var body: some Scene {
//        WindowGroup {
//            // A simple placeholder view. The real work happens in .onAppear
//            Text("Testing inference in console... Check your Xcode debug output.")
//                .padding()
//                .onAppear(perform: runInferenceTest) // Run our test when the app launches
//        }
//    }
//    
//    private func runInferenceTest() {
//        print("--- STARTING RAW INFERENCE TEST ---")
//        
//        // 1. Initialize the model handler
//        guard let modelHandler = YOLOv5ModelHandler() else {
//            print("❌ TEST FAILED: Model handler failed to initialize.")
//            return
//        }
//        print("✅ Model handler initialized.")
//        
//        // 2. Load the test image from assets
//        guard let uiImage = UIImage(named: "TestImage") else {
//            print("❌ TEST FAILED: Could not find 'TestImage'.")
//            return
//        }
//        print("✅ TestImage loaded.")
//        
//        // 3. Convert the UIImage to the CVPixelBuffer format the model needs
//        guard let pixelBuffer = uiImage.toCVPixelBuffer() else {
//            print("❌ TEST FAILED: Failed to convert UIImage to CVPixelBuffer.")
//            return
//        }
//        print("✅ Image converted to PixelBuffer successfully.")
//        
//        // 4. Perform the detection
//        print("▶️ Performing detection...")
//        
//        // Call the asynchronous function and handle the result
//        modelHandler.performDetection(on: pixelBuffer) { result in
//            // Switch back to the main thread to print results
//            DispatchQueue.main.async {
//                print("\n--- INFERENCE COMPLETE ---")
//                
//                switch result {
//                case .success(let (box, confidence)):
//                    if let conf = confidence, let box = box {
//                        print("✅ SUCCESS: Model returned a prediction!")
//                        print("Confidence: \(conf)")
//                        print("Normalized Bounding Box: \(box)")
//                    } else {
//                        print("ℹ️ INFO: Model ran successfully but found no objects above the threshold.")
//                    }
//                    
//                case .failure(let error):
//                    print("❌ FAILURE: Detection failed with an error: \(error.localizedDescription)")
//                }
//                
//                print("--- END OF TEST ---")
//            }
//        }
//    }
//}
//
//// Helper extension to convert UIImage to CVPixelBuffer
//// This extension must be outside the main App struct.
//extension UIImage {
//    func toCVPixelBuffer() -> CVPixelBuffer? {
//        let attrs = [
//            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
//            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
//        ] as CFDictionary
//        
//        var pixelBuffer: CVPixelBuffer?
//        let status = CVPixelBufferCreate(
//            kCFAllocatorDefault,
//            Int(self.size.width),
//            Int(self.size.height),
//            kCVPixelFormatType_32ARGB,
//            attrs,
//            &pixelBuffer
//        )
//        
//        guard status == kCVReturnSuccess, let unwrappedPixelBuffer = pixelBuffer else {
//            return nil
//        }
//        
//        CVPixelBufferLockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
//        let pixelData = CVPixelBufferGetBaseAddress(unwrappedPixelBuffer)
//        
//        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
//        guard let context = CGContext(
//            data: pixelData,
//            width: Int(self.size.width),
//            height: Int(self.size.height),
//            bitsPerComponent: 8,
//            bytesPerRow: CVPixelBufferGetBytesPerRow(unwrappedPixelBuffer),
//            space: rgbColorSpace,
//            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
//        ) else {
//            return nil
//        }
//        
//        context.translateBy(x: 0, y: self.size.height)
//        context.scaleBy(x: 1.0, y: -1.0)
//        
//        UIGraphicsPushContext(context)
//        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
//        UIGraphicsPopContext()
//        CVPixelBufferUnlockBaseAddress(unwrappedPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
//        
//        return unwrappedPixelBuffer
//    }
//}
