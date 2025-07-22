//
//  CameraPicker.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-06.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// A custom UIImagePickerController subclass that forces landscape orientation.
class LandscapeUIImagePickerController: UIImagePickerController {
    
    // This controller only supports landscape orientations.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    // This sets the initial orientation preference to landscape right.
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        // Use our custom landscape-only picker controller.
        let picker = LandscapeUIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        
        // --- Orientation Hack ---
        // The following line is a common technique to programmatically suggest a
        // device orientation change. It uses a private API, which can be risky
        // for App Store submissions, but is often necessary to force the UI to rotate.
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // You can add code here if you need to update the controller.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.videoURL = url
            }
            
            // After finishing, dismiss the camera view.
            // If the rest of your app is portrait-only, you might need to
            // programmatically rotate back to portrait here before dismissing.
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            // Dismiss the camera view if the user cancels.
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
