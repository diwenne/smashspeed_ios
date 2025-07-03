//
//  ImageProcessor.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-07-01.
//

import Foundation
import CoreImage
import VideoToolbox

enum ImageProcessorError: Error {
    case failedToCreatePixelBuffer
    case failedToCreateCGImage
    case failedToCreateContext
}

/// A helper class to handle image preprocessing, specifically resizing and letterboxing.
class ImageProcessor {

    /// Resizes a CVPixelBuffer to a target size using letterboxing to maintain aspect ratio.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The source `CVPixelBuffer` to resize.
    ///   - targetSize: The target dimensions (e.g., 640x640) for the model input.
    /// - Returns: A new, resized `CVPixelBuffer`.
    /// - Throws: An `ImageProcessorError` if any step of the conversion or rendering fails.
    static func resizePixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        to targetSize: CGSize
    ) throws -> CVPixelBuffer {
        
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let sourceSize = sourceImage.extent.size

        // Calculate aspect ratios
        let sourceAspectRatio = sourceSize.width / sourceSize.height
        let targetAspectRatio = targetSize.width / targetSize.height

        // Determine the scale factor and the new size to maintain aspect ratio
        var scaleX = targetSize.width / sourceSize.width
        var scaleY = targetSize.height / sourceSize.height

        if sourceAspectRatio > targetAspectRatio {
            // Source is wider than target -> fit to width
            scaleY = scaleX
        } else {
            // Source is taller than or equal to target -> fit to height
            scaleX = scaleY
        }
        
        let scaledImageSize = CGSize(width: sourceSize.width * scaleX, height: sourceSize.height * scaleY)
        
        // Center the scaled image
        let originX = (targetSize.width - scaledImageSize.width) / 2
        let originY = (targetSize.height - scaledImageSize.height) / 2
        let translationTransform = CGAffineTransform(translationX: originX, y: originY)
        
        let scaledImage = sourceImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY)).transformed(by: translationTransform)

        // --- NEW/MODIFIED SECTION ---
        // Create a solid gray background image that matches the YOLOv5 letterbox color.
        // The color values are divided by 255 because CIColor expects values from 0.0 to 1.0.
        let grayColor = CIColor(red: 114/255.0, green: 114/255.0, blue: 114/255.0)
        let backgroundImage = CIImage(color: grayColor).cropped(to: CGRect(origin: .zero, size: targetSize))
        
        // Composite the scaled image on top of the gray background.
        let finalImage = scaledImage.composited(over: backgroundImage)
        // --- END OF NEW/MODIFIED SECTION ---

        // Create a new pixel buffer for the output
        var newPixelBuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &newPixelBuffer
        )

        guard status == kCVReturnSuccess, let unwrappedBuffer = newPixelBuffer else {
            throw ImageProcessorError.failedToCreatePixelBuffer
        }

        // Render the final composited image into the new CVPixelBuffer
        let context = CIContext()
        context.render(finalImage, to: unwrappedBuffer)
        
        return unwrappedBuffer
    }
}
