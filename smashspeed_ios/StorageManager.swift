//
//  StorageManager.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-05.
//


import Foundation
import FirebaseStorage

// --- ADDED ---: A new class to handle all Firebase Storage operations.
class StorageManager {
    
    static let shared = StorageManager()
    private let storage = Storage.storage()
    
    private init() {}
    
    /// Uploads a video to Firebase Storage and returns the public download URL.
    /// - Parameters:
    ///   - localURL: The URL of the video file on the user's device.
    ///   - userID: The ID of the user to associate the video with.
    /// - Returns: The public URL to access the video after upload.
    func uploadVideo(localURL: URL, for userID: String) async throws -> URL {
        // Create a unique path in Firebase Storage for the video.
        let storageRef = storage.reference().child("videos/\(userID)/\(UUID().uuidString).mov")
        
        // Upload the file from the local URL.
        _ = try await storageRef.putFileAsync(from: localURL, metadata: nil)
        
        // Get the public download URL for the uploaded file.
        let downloadURL = try await storageRef.downloadURL()
        return downloadURL
    }
}
