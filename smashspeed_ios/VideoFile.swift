//
//  VideoFile.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-05.
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoFile: Transferable, Equatable {
    let url: URL
    
    // This function is required by the Equatable protocol.
    static func == (lhs: VideoFile, rhs: VideoFile) -> Bool {
        return lhs.url == rhs.url
    }
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movieFile in
            SentTransferredFile(movieFile.url)
        } importing: { received in
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileName = received.file.lastPathComponent
            let copyURL = tempDirectory.appendingPathComponent(fileName)
            
            if FileManager.default.fileExists(atPath: copyURL.path) {
                try FileManager.default.removeItem(at: copyURL)
            }
            
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            
            return Self.init(url: copyURL)
        }
    }
}
