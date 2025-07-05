//
//  DetectView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//

import SwiftUI
import PhotosUI

extension SmashSpeedViewModel.AppState: Equatable {
    static func == (lhs: SmashSpeedViewModel.AppState, rhs: SmashSpeedViewModel.AppState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.review, .review): return true
        case (.awaitingCalibration, .awaitingCalibration): return true
        case (.processing, .processing): return true
        case (.completed, .completed): return true
        case (.error, .error): return true
        default: return false
        }
    }
}


struct DetectView: View {
    @StateObject private var viewModel = SmashSpeedViewModel()
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    
    @State private var selectedItem: PhotosPickerItem?
    
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            switch viewModel.appState {
            
            case .idle:
                MainView(selectedItem: $selectedItem)
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            do {
                                if let item = newItem,
                                   let videoFile = try await item.loadTransferable(type: VideoFile.self) {
                                    
                                    viewModel.videoSelected(url: videoFile.url)
                                    selectedItem = nil
                                }
                            } catch {
                                print("Error loading video file: \(error)")
                            }
                        }
                    }
                    .navigationTitle("Detect")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            AppLogoView() // Assuming this view exists
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { showOnboarding = true }) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
            
            case .review(let videoURL, let result):
                ReviewView(videoURL: videoURL, initialResult: result) { editedFrames in
                    viewModel.finishReview(
                        andShowResultsFrom: editedFrames,
                        for: authViewModel.user?.uid,
                        videoURL: videoURL
                    )
                }
            
            case .awaitingCalibration(let url):
                CalibrationView(videoURL: url, onComplete: { scaleFactor in
                    viewModel.startProcessing(videoURL: url, scaleFactor: scaleFactor)
                }, onCancel: {
                    viewModel.cancelCalibration()
                })
                
            case .processing(let progress):
                ProcessingView(progress: progress) { viewModel.cancelProcessing() }
                
            case .completed(let speed):
                ResultView(speed: speed, onReset: viewModel.reset)
                
            case .error(let message):
                ErrorView(message: message, onReset: viewModel.reset)
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { // Assuming this view exists
                showOnboarding = false
            }
        }
    }
}

// MARK: - Subviews for DetectView

struct MainView: View {
    @Binding var selectedItem: PhotosPickerItem?
    
    var body: some View {
        VStack {
            Spacer()

            PhotosPicker(
                selection: $selectedItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                ZStack {
                    Circle()
                        .fill(Color.blue.gradient)
                        .frame(width: 140, height: 140)
                        .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)
                    
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                }
            }
            .padding()

            Text("Select a video to begin")
                .font(.headline)
                .padding(.top)

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
            }.padding(.horizontal, 40)
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
            Text(String(format: "%.1f", speed)).font(.system(size: 80, weight: .bold, design: .rounded)).foregroundColor(.blue)
            Text("km/h").font(.title2).foregroundColor(.secondary)
            Button(action: onReset) {
                Label("Analyze Another Video", systemImage: "arrow.uturn.backward.circle")
            }.buttonStyle(.bordered).padding(.top, 40)
        }
    }
}

struct ErrorView: View {
    let message: String
    let onReset: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.red)
            Text(message).multilineTextAlignment(.center).padding()
            Button("Try Again", action: onReset).buttonStyle(.borderedProminent)
        }
    }
}
