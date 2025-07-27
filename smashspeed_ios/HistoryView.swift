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
import CoreGraphics

// MARK: - Main History View

struct HistoryView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @StateObject private var historyViewModel = HistoryViewModel()
    
    @State private var showDeleteConfirmation = false
    @State private var resultToDelete: DetectionResult?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
                Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)
                
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
                                .font(.subheadline).foregroundColor(.secondary).padding()
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

// MARK: - Subviews

struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack { Text(label); Spacer(); Text(value).fontWeight(.bold).foregroundColor(.secondary) }
    }
}

struct HistoryRow: View {
    let result: DetectionResult
    
    var body: some View {
        let destination = ResultDetailView(result: result)

        let rowContent = HStack {
            if result.videoURL != nil, result.frameData != nil {
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
        
        if result.videoURL != nil, result.frameData != nil {
            NavigationLink(destination: destination) {
                rowContent
            }
        } else {
            rowContent
        }
    }
}

// MARK: - Detail View with Embedded Player

@MainActor
class ResultDetailViewModel: ObservableObject {
    let player: AVPlayer
    let frameData: [FrameData]
    let originalAsset: AVAsset

    @Published var currentSpeed: Double = 0.0
    @Published var currentBoundingBox: CGRect? = nil
    @Published var videoSize: CGSize = .zero
    
    private var timeObserver: Any?

    init(result: DetectionResult) {
        if let videoURLString = result.videoURL, let url = URL(string: videoURLString) {
            let asset = AVURLAsset(url: url)
            self.originalAsset = asset
            self.player = AVPlayer(url: url)
        } else {
            self.originalAsset = AVAsset()
            self.player = AVPlayer()
        }
        self.frameData = result.frameData ?? []
        
        Task {
            await loadVideoSize()
            startObserving()
        }
    }
    
    private func loadVideoSize() async {
        guard let track = try? await originalAsset.loadTracks(withMediaType: .video).first else { return }
        self.videoSize = await track.naturalSize
    }
    
    func startObserving() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentTime = time.seconds
            let currentFrame = self.frameData.min(by: { abs($0.timestamp - currentTime) < abs($1.timestamp - currentTime) })

            if let currentFrame = currentFrame {
                self.currentSpeed = currentFrame.speedKPH
                self.currentBoundingBox = currentFrame.boundingBox.toCGRect()
            }
        }
    }
    
    func stopObserving() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
}

struct ResultDetailView: View {
    @StateObject private var viewModel: ResultDetailViewModel
    private let result: DetectionResult

    @State private var shareableImage: UIImage?

    init(result: DetectionResult) {
        self.result = result
        _viewModel = StateObject(wrappedValue: ResultDetailViewModel(result: result))
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: 150, y: -200)
            Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: -150, y: 250)

            ScrollView {
                VStack(spacing: 20) {
                    videoPlayerSection
                    detailsSection
                }
                .padding()
            }
        }
        .navigationTitle("Smash Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.player.play() }
        .onDisappear {
            viewModel.player.pause()
            viewModel.stopObserving()
        }
        .sheet(item: $shareableImage) { image in
            SharePreviewView(image: image)
        }
    }

    private var videoPlayerSection: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                VideoPlayer(player: viewModel.player)
                
                if let box = viewModel.currentBoundingBox, viewModel.videoSize != .zero {
                    let videoFrame = AVMakeRect(aspectRatio: viewModel.videoSize, insideRect: geometry.frame(in: .local))
                    let viewRect = CGRect(
                        x: videoFrame.origin.x + (box.origin.x * videoFrame.width),
                        y: videoFrame.origin.y + (box.origin.y * videoFrame.height),
                        width: box.width * videoFrame.width,
                        height: box.height * videoFrame.height
                    )
                    Rectangle()
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: viewRect.width, height: viewRect.height)
                        .position(x: viewRect.midX, y: viewRect.midY)
                }
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10)
    }
    
    private var detailsSection: some View {
        ZStack {
            VStack(spacing: 15) {
                Text("Peak Speed")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text(String(format: "%.1f km/h", result.peakSpeedKph))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Divider()
                
                if let angle = result.angle {
                    HStack {
                        Text("Smash Angle:")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.0f° downward", angle))
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal)
                }

                HStack {
                    Text("Live Speed:")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f km/h", viewModel.currentSpeed))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal)

                Divider()

                Text("Frame Data")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                VStack {
                    ForEach(viewModel.frameData, id: \.self) { frame in
                        VStack {
                            HStack {
                                Text("Time: \(String(format: "%.2f", frame.timestamp))s")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(String(format: "%.1f", frame.speedKPH)) km/h")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 4)
                            
                            if frame != viewModel.frameData.last {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: renderImageForSharing) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .font(.title3)
                    .padding(10)
                    .clipShape(Circle())
                }
                Spacer()
            }
            .padding([.top, .trailing], 12)
        }
    }
    
    @MainActor
    private func renderImageForSharing() {
        let shareView = ShareableView(speed: result.peakSpeedKph)
        self.shareableImage = shareView.snapshot()
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
    var detectionCount: Int { detectionResults.count }
    
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
    
    static func saveResult(peakSpeedKph: Double, angle: Double?, for userID: String, videoURL: String, frameData: [FrameData]) throws {
        let db = Firestore.firestore()
        let result = DetectionResult(
            userID: userID,
            date: Timestamp(date: Date()),
            peakSpeedKph: peakSpeedKph,
            angle: angle,
            videoURL: videoURL,
            frameData: frameData
        )
        try db.collection("detections").addDocument(from: result)
    }
    
    func deleteResult(_ result: DetectionResult) {
        Task {
            do {
                if let videoURLString = result.videoURL {
                    let storageRef = Storage.storage().reference(forURL: videoURLString)
                    try await storageRef.delete()
                }
                if let docID = result.id {
                    try await db.collection("detections").document(docID).delete()
                }
            } catch {
                #if DEBUG
                print("Error deleting result: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

