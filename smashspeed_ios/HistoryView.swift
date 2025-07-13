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
    
    // State for the delete confirmation alert
    @State private var showDeleteConfirmation = false
    @State private var resultToDelete: DetectionResult?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 1. A monochromatic blue aurora background to match other views.
                Color(.systemBackground).ignoresSafeArea()
                
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .blur(radius: 150)
                    .offset(x: -150, y: -200)

                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .blur(radius: 180)
                    .offset(x: 150, y: 150)
                
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
                // Add the confirmation alert modifier here
                .alert("Confirm Deletion", isPresented: $showDeleteConfirmation, presenting: resultToDelete) { result in
                    Button("Delete", role: .destructive) {
                        historyViewModel.deleteResult(result)
                    }
                } message: { result in
                    Text("Are you sure you want to delete the result from \(result.date.dateValue().formatted(date: .abbreviated, time: .shortened))? This action cannot be undone.")
                }
            }
        }
    }
    
    @ViewBuilder
    private func content(for userID: String) -> some View {
        if historyViewModel.detectionResults.isEmpty {
            VStack {
                ContentUnavailableView("No Results", systemImage: "list.bullet.clipboard", description: Text("Your analyzed smashes will appear here."))
            }
            .padding(40)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
            .padding()
        } else {
            List {
                // Overall Stats Panel
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Overall Stats").font(.headline).padding(.bottom, 5)
                        StatRow(label: "Top Speed", value: String(format: "%.1f km/h", historyViewModel.topSpeed))
                        Divider()
                        StatRow(label: "Average Speed", value: String(format: "%.1f km/h", historyViewModel.averageSpeed))
                        Divider()
                        StatRow(label: "Total Smashes", value: "\(historyViewModel.detectionCount)")
                    }
                    .padding(20)
                    .background(GlassPanel())
                    .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))

                // Progress Chart Panel
                Section {
                    VStack(alignment: .leading) {
                        Text("Progress Over Time").font(.headline).padding([.top, .leading], 5)
                        if historyViewModel.detectionResults.count > 1 {
                            Chart {
                                ForEach(historyViewModel.detectionResults.reversed()) { result in
                                    LineMark(
                                        x: .value("Date", result.date.dateValue(), unit: .day),
                                        y: .value("Speed", result.peakSpeedKph)
                                    ).interpolationMethod(.catmullRom)
                                    .foregroundStyle(Color.accentColor)

                                    PointMark(
                                        x: .value("Date", result.date.dateValue(), unit: .day),
                                        y: .value("Speed", result.peakSpeedKph)
                                    ).foregroundStyle(Color.accentColor)
                                }
                            }
                            .chartYScale(domain: 0...(historyViewModel.topSpeed * 1.2))
                            .frame(height: 200)
                        } else {
                            Text("Analyze at least two smashes to see your progress chart.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .padding(25)
                    .background(GlassPanel())
                    .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
                
                // History List Section
                Section(header: Text("History").padding(.leading)) {
                    ForEach(historyViewModel.detectionResults) { result in
                        HistoryRow(result: result)
                            .padding()
                            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                            .background(GlassPanel())
                            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    resultToDelete = result
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                .tint(.red)
                            }
                    }
                    // FIX: Add the .onDelete modifier back to enable the EditButton functionality.
                    .onDelete { indexSet in
                        guard let index = indexSet.first else { return }
                        resultToDelete = historyViewModel.detectionResults[index]
                        showDeleteConfirmation = true
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .toolbar { EditButton() }
        }
    }
    
    private var loggedOutView: some View {
        VStack {
             ContentUnavailableView("Log In Required", systemImage: "person.crop.circle.badge.questionmark", description: Text("Please sign in to view results."))
        }
        .padding(40)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .padding()
    }
}

// MARK: - Subviews & Player

struct HistoryRow: View {
    let result: DetectionResult
    var body: some View {
        let destination = result.videoURL.flatMap(URL.init).map(VideoPlayerView.init)

        let rowContent = HStack {
            if destination != nil {
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

        if let destinationView = destination {
            NavigationLink(destination: destinationView) {
                rowContent
            }
        } else {
            rowContent
        }
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
                #if DEBUG
                print("Error fetching snapshot: \(error?.localizedDescription ?? "Unknown error")")
                #endif
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
    
    // This method now takes a specific result to delete.
    func deleteResult(_ result: DetectionResult) {
        Task {
            do {
                if let videoURLString = result.videoURL {
                    let storageRef = Storage.storage().reference(forURL: videoURLString)
                    try await storageRef.delete()
                    #if DEBUG
                    print("Successfully deleted video from Storage.")
                    #endif
                }
                
                if let docID = result.id {
                    try await db.collection("detections").document(docID).delete()
                    #if DEBUG
                    print("Successfully deleted document from Firestore.")
                    #endif
                }
            } catch {
                #if DEBUG
                print("Error deleting result: \(error.localizedDescription)")
                #endif
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
