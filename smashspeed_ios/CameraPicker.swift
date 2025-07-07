//
//  CameraPicker.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-06.
//


//
//  CameraPicker.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-06.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CameraPicker: UIViewControllerRepresentable {
    // This binding will be used to pass the URL of the recorded video back to our main view.
    @Binding var videoURL: URL?
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier] // We only want to record videos
        picker.videoQuality = .typeHigh
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // The Coordinator acts as a bridge to handle events from the camera view.
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        // This function is called when the user finishes recording a video.
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Get the URL of the video file that was just saved.
            if let url = info[.mediaURL] as? URL {
                parent.videoURL = url
            }
            // Dismiss the camera view.
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            // Dismiss the camera view if the user cancels.
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}