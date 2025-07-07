//
//  HistoryView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-05.
//

import SwiftUI
import FirebaseFirestore
import Combine
import Charts
import FirebaseAuth
import AVKit
import FirebaseStorage

// MARK: - Main History View

struct HistoryView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @StateObject private var historyViewModel = HistoryViewModel()
    
    var body: some View {
        NavigationStack {
            VStack {
                if authViewModel.isSignedIn, let user = authViewModel.user {
                    content(for: user.uid)
                } else {
                    loggedOutView
                }
            }
            .navigationTitle("Results")
            .onAppear {
                if let userID = authViewModel.user?.uid {
                    historyViewModel.subscribe(to: userID)
                }
            }
        }
    }
    
    @ViewBuilder
    private func content(for userID: String) -> some View {
        if historyViewModel.detectionResults.isEmpty {
            ContentUnavailableView("No Results", systemImage: "list.bullet.clipboard", description: Text("Your analyzed smashes will appear here."))
        } else {
            List {
                Section(header: Text("Overall Stats")) {
                    StatRow(label: "Top Speed", value: String(format: "%.1f km/h", historyViewModel.topSpeed))
                    StatRow(label: "Average Speed", value: String(format: "%.1f km/h", historyViewModel.averageSpeed))
                    StatRow(label: "Total Smashes", value: "\(historyViewModel.detectionCount)")
                }
                
                Section("Progress Over Time") {
                    if historyViewModel.detectionResults.count > 1 {
                        Chart {
                            ForEach(historyViewModel.detectionResults.reversed()) { result in
                                LineMark(
                                    x: .value("Date", result.date.dateValue(), unit: .day),
                                    y: .value("Speed", result.peakSpeedKph)
                                ).interpolationMethod(.catmullRom)

                                PointMark(
                                    x: .value("Date", result.date.dateValue(), unit: .day),
                                    y: .value("Speed", result.peakSpeedKph)
                                ).foregroundStyle(.blue)
                            }
                        }
                        .chartYScale(domain: 0...(historyViewModel.topSpeed * 1.2))
                        .frame(height: 200)
                        .padding(.vertical)
                    } else {
                        Text("Analyze at least two smashes to see your progress chart.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("History")) {
                    ForEach(historyViewModel.detectionResults) { result in
                        if let videoURLString = result.videoURL, let videoURL = URL(string: videoURLString) {
                            NavigationLink(destination: VideoPlayerView(videoURL: videoURL)) {
                                HistoryRow(result: result)
                            }
                        } else {
                            HistoryRow(result: result)
                        }
                    }
                    .onDelete { indexSet in
                        historyViewModel.deleteResult(at: indexSet)
                    }
                }
            }
            .toolbar { EditButton() }
        }
    }
    
    private var loggedOutView: some View {
        ContentUnavailableView("Log In Required", systemImage: "person.crop.circle.badge.questionmark", description: Text("Please sign in to view results."))
    }
}

// MARK: - Subviews & Player

struct HistoryRow: View {
    let result: DetectionResult
    var body: some View {
        HStack {
            if result.videoURL != nil {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title2)
            }
            VStack(alignment: .leading) {
                Text(result.date.dateValue(), style: .date).font(.headline)
                Text(result.date.dateValue(), style: .time).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(result.formattedSpeed).font(.title2).fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack { Text(label); Spacer(); Text(value).fontWeight(.bold).foregroundColor(.secondary) }
    }
}

class PlayerViewModel: ObservableObject {
    let player: AVPlayer
    @Published var status: AVPlayer.Status = .unknown
    private var statusObserver: NSKeyValueObservation?
    init(url: URL) {
        self.player = AVPlayer(url: url)
        self.statusObserver = self.player.observe(\.status, options: [.new]) { player, change in
            DispatchQueue.main.async {
                self.status = player.status
                if player.status == .readyToPlay {
                    player.play()
                }
            }
        }
    }
}

struct VideoPlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    init(videoURL: URL) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(url: videoURL))
    }
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            switch viewModel.status {
            case .readyToPlay:
                VideoPlayer(player: viewModel.player).edgesIgnoringSafeArea(.all)
            case .failed:
                VStack {
                    Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundColor(.red)
                    Text("Video Failed to Load").foregroundColor(.white).padding(.top, 8)
                }
            case .unknown:
                ProgressView().tint(.white)
            @unknown default:
                EmptyView()
            }
        }
        .navigationTitle("Smash Replay")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: []) }
        .onDisappear { viewModel.player.pause() }
    }
}

// MARK: - History View Model

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var detectionResults = [DetectionResult]()
    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    var topSpeed: Double { detectionResults.map { $0.peakSpeedKph }.max() ?? 0.0 }
    var averageSpeed: Double {
        let speeds = detectionResults.map { $0.peakSpeedKph }
        return speeds.isEmpty ? 0.0 : speeds.reduce(0, +) / Double(speeds.count)
    }
    var detectionCount: Int {
        detectionResults.count
    }
    
    func subscribe(to userID: String) {
        if listenerRegistration != nil { unsubscribe() }
        let query = db.collection("detections").whereField("userID", isEqualTo: userID).order(by: "date", descending: true)
        listenerRegistration = query.addSnapshotListener { [weak self] (snapshot, error) in
            guard let docs = snapshot?.documents, error == nil else {
                print("Error fetching snapshot: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            self?.detectionResults = docs.compactMap { try? $0.data(as: DetectionResult.self) }
        }
    }
    
    func unsubscribe() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        detectionResults = []
    }
    
    static func saveResult(peakSpeedKph: Double, for userID: String, videoURL: String) throws {
        let db = Firestore.firestore()
        let result = DetectionResult(
            userID: userID,
            date: Timestamp(date: Date()),
            peakSpeedKph: peakSpeedKph,
            videoURL: videoURL
        )
        try db.collection("detections").addDocument(from: result)
    }
    
    func deleteResult(at offsets: IndexSet) {
            let resultsToDelete = offsets.map { self.detectionResults[$0] }
            
            for result in resultsToDelete {
                Task { // Use a Task to perform asynchronous operations
                    do {
                        // 1. Delete from Firebase Storage if a video URL exists
                        if let videoURLString = result.videoURL {
                            let storageRef = Storage.storage().reference(forURL: videoURLString)
                            try await storageRef.delete()
                            print("Successfully deleted video from Storage.")
                        }
                        
                        // 2. Delete from Firestore after storage deletion is successful
                        if let docID = result.id {
                            try await db.collection("detections").document(docID).delete()
                            print("Successfully deleted document from Firestore.")
                        }
                    } catch {
                        print("Error deleting result: \(error.localizedDescription)")
                        // Optionally, you could add a state to show an error to the user here.
                    }
                }
            }
        }
}

// --- MODIFIED ---: Add the videoURL property to your data model.
struct DetectionResult: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let userID: String
    let date: Timestamp
    let peakSpeedKph: Double
    var videoURL: String? // --- ADDED ---: The URL of the video in Firebase Storage.
    
    var formattedSpeed: String { String(format: "%.1f km/h", peakSpeedKph) }
}
