//
//  ContentView.swift
//  smashspeed
//
//  Created by Diwen Huang on 2025-06-27.
//

import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = SmashSpeedViewModel()
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        switch viewModel.appState {
        // Corrected case to pass the single 'result' object
        case .review(let videoURL, let result):
            ReviewView(videoURL: videoURL, initialResult: result) { editedResults in
                viewModel.finishReview(andShowResultsFrom: editedResults)
            }
        
        // All other cases remain the same
        case .idle:
            MainView(selectedItem: $selectedItem)
                .onChange(of: selectedItem) { newItem in
                    Task {
                        if let url = await getVideoURL(from: newItem) {
                            viewModel.videoSelected(url: url)
                            selectedItem = nil
                        }
                    }
                }
        case .awaitingCalibration(let url):
            CalibrationView(videoURL: url, onComplete: { scaleFactor in
                viewModel.startProcessing(videoURL: url, scaleFactor: scaleFactor)
            }, onCancel: {
                viewModel.cancelCalibration()
            })
            
        case .processing(let progress):
            ProcessingView(progress: progress) { viewModel.reset() }
            
        case .completed(let speed):
            ResultView(speed: speed, onReset: viewModel.reset)
            
        case .error(let message):
            ErrorView(message: message, onReset: viewModel.reset)
        }
    }
    
    private func getVideoURL(from item: PhotosPickerItem?) async -> URL? {
        guard let item = item else { return nil }
        do {
            guard let videoData = try await item.loadTransferable(type: Data.self) else { return nil }
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let fileName = "\(UUID().uuidString).mov"
            let temporaryURL = temporaryDirectory.appendingPathComponent(fileName)
            try videoData.write(to: temporaryURL)
            return temporaryURL
        } catch {
            print("An error occurred while getting the video URL: \(error)")
            return nil
        }
    }
}

// MARK: - Subviews for each state

struct MainView: View {
    @Binding var selectedItem: PhotosPickerItem?
    
    var body: some View {
        VStack {
            HStack {
                Image("AppIconPreview")
                    .resizable().frame(width: 24, height: 24).foregroundColor(.blue)
                Text("SmashSpeed").font(.headline).fontWeight(.semibold)
                Spacer()
            }
            .padding([.top, .leading], 16)
            
            Spacer()
            
            PhotosPicker(
                selection: $selectedItem,
                matching: .videos, // We only want videos
                photoLibrary: .shared()
            ) {
                ZStack {
                    Circle().fill(Color.blue).frame(width: 120, height: 120)
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.white).font(.system(size: 50))
                }
            }
            .padding()
            
            Text("Select a video to begin").font(.caption).padding(.top)
            
            Spacer()
        }
    }
}

struct ProcessingView: View {
    let progress: Progress
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Analyzing Video...").font(.title2)
            ProgressView(value: progress.fractionCompleted) {
               Text("\(Int(progress.fractionCompleted * 100))%")
            }
            .padding(.horizontal, 40)
            Button("Cancel", role: .destructive, action: onCancel)
        }
    }
}

struct ResultView: View {
    let speed: Double
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Maximum Speed").font(.title).foregroundColor(.secondary)
            Text(String(format: "%.1f", speed))
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
            Text("km/h").font(.title2).foregroundColor(.secondary)
            Button(action: onReset) {
                Label("Analyze Another Video", systemImage: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.bordered).padding(.top, 40)
        }
    }
}

struct ErrorView: View {
    let message: String
    let onReset: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundColor(.red)
            Text(message).multilineTextAlignment(.center).padding()
            Button("Try Again", action: onReset).buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
}
