//
//  DetectView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//

import SwiftUI
import PhotosUI

// This Equatable extension matches the simplified AppState
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
    
    // State variables for the input methods
    @State private var selectedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var recordedVideoURL: URL?
    
    // State to control our custom pop-up menu
    @State private var showInputSelector = false
    
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            switch viewModel.appState {
            
            case .idle:
                MainView(showInputSelector: $showInputSelector)
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let item = newItem,
                               let videoFile = try? await item.loadTransferable(type: VideoFile.self) {
                                viewModel.videoSelected(url: videoFile.url)
                                selectedItem = nil
                            }
                        }
                    }
                    .onChange(of: recordedVideoURL) { _, newURL in
                        if let url = newURL {
                            viewModel.videoSelected(url: url)
                            recordedVideoURL = nil
                        }
                    }
                    .navigationTitle("Detect")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) { AppLogoView() }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { showOnboarding = true }) {
                                Image(systemName: "info.circle").foregroundColor(.accentColor)
                            }
                        }
                    }
            
            case .review(let videoURL, let result):
                ReviewView(videoURL: videoURL, initialResult: result) { editedFrames in
                    viewModel.finishReview(andShowResultsFrom: editedFrames, for: authViewModel.user?.uid, videoURL: videoURL)
                }
            case .awaitingCalibration(let url):
                CalibrationView(videoURL: url, onComplete: { scaleFactor in
                    viewModel.startProcessing(videoURL: url, scaleFactor: scaleFactor)
                }, onCancel: { viewModel.cancelCalibration() })
            case .processing(let progress):
                ProcessingView(progress: progress) { viewModel.cancelProcessing() }
            case .completed(let speed):
                ResultView(speed: speed, onReset: viewModel.reset)
            case .error(let message):
                ErrorView(message: message, onReset: viewModel.reset)
            }
        }
        .sheet(isPresented: $showInputSelector) {
            InputSourceSelectorView(
                isPresented: $showInputSelector,
                showCamera: $showCamera,
                selectedItem: $selectedItem
            )
            .presentationDetents([.height(220)])
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(videoURL: $recordedVideoURL)
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView { showOnboarding = false } }
    }
}

// MARK: - Subviews for DetectView

// MainView is now back to the simple, single button UI
struct MainView: View {
    @Binding var showInputSelector: Bool
    
    var body: some View {
        VStack {
            Spacer()
            Button {
                showInputSelector = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.blue.gradient)
                        .frame(width: 140, height: 140)
                        .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)
                    
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 60, weight: .thin))
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

// This is the custom pop-up sheet with the two choices
struct InputSourceSelectorView: View {
    @Binding var isPresented: Bool
    @Binding var showCamera: Bool
    @Binding var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 16) {
            // Title for the pop-up
            Text("Analyze a Smash")
                .font(.headline)
                .padding(.top)
                .padding(.bottom, 8)

            // Button to open the camera
            Button {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showCamera = true
                }
            } label: {
                Label("Record New Video", systemImage: "camera.fill")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            
            // Button to open the photo library
            PhotosPicker(
                selection: $selectedItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                Label("Choose from Library", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .onChange(of: selectedItem) { _, _ in
                // When a video is picked, close the pop-up.
                isPresented = false
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}


// These subviews are unchanged
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
