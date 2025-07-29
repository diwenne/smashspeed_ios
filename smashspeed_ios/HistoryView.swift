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

// MARK: - Helper Types for History View

/// Enum for selecting the time range for filters.
enum TimeRange: String, CaseIterable, Identifiable {
    case week = "Past Week"
    case month = "Past Month"
    case all = "All Time"
    var id: Self { self }
}

/// A struct to hold aggregated data for the chart.
struct DailyTopSpeed: Identifiable {
    let id = UUID()
    let date: Date
    let topSpeed: Double
}


// MARK: - Main History View

struct HistoryView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @StateObject private var historyViewModel = HistoryViewModel()
    
    // --- STATE FOR FILTERS ---
    @State private var selectedRange: TimeRange = .week
    @State private var speedFilterEnabled = false
    @State private var minimumSpeed: Double = 150.0
    
    // --- STATE FOR UI ---
    @State private var showDeleteConfirmation = false
    @State private var resultToDelete: DetectionResult?
    @State private var selectedDataPoint: DailyTopSpeed?
    @State private var showChartValue = false
    
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
                // --- REACTIVE FILTER APPLICATION ---
                .onChange(of: selectedRange) { _ in applyFilters() }
                .onChange(of: speedFilterEnabled) { _ in applyFilters() }
                .onChange(of: minimumSpeed) { _ in applyFilters() }
                .onChange(of: historyViewModel.allResults) { _ in applyFilters() }
                .alert("Confirm Deletion", isPresented: $showDeleteConfirmation, presenting: resultToDelete) { result in
                    Button("Delete", role: .destructive) {
                        historyViewModel.deleteResult(result)
                    }
                } message: { result in
                    Text("Are you sure you want to delete this result? This action cannot be undone.")
                }
            }
        }
    }
    
    /// Triggers the ViewModel to re-calculate its filtered data.
    private func applyFilters() {
        historyViewModel.applyFilters(
            range: selectedRange,
            speedFilterEnabled: speedFilterEnabled,
            minSpeed: minimumSpeed
        )
    }
    
    /// The main content view when the user is logged in.
    @ViewBuilder
    private func content(for userID: String) -> some View {
        if historyViewModel.allResults.isEmpty {
            emptyStateView
        } else {
            List {
                statsSection
                progressChartSection
                filterControlsSection
                historyListSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    /// View displayed when there are no results at all.
    private var emptyStateView: some View {
        VStack {
             ContentUnavailableView("No Results", systemImage: "list.bullet.clipboard", description: Text("Your analyzed smashes will appear here."))
        }
        .padding(40)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .padding()
    }
    
    /// View for "Overall Stats" - reflects current filters.
    private var statsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filtered Stats").font(.headline).padding(.bottom, 5)
                StatRow(label: "Top Speed", value: String(format: "%.1f km/h", historyViewModel.filteredTopSpeed))
                Divider()
                StatRow(label: "Average Speed", value: String(format: "%.1f km/h", historyViewModel.filteredAverageSpeed))
                Divider()
                StatRow(label: "Total Smashes", value: "\(historyViewModel.filteredDetectionCount)")
            }
            .padding(20)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        }
        .listRowStyling()
    }
    
    /// View for the "Progress Over Time" chart.
    private var progressChartSection: some View {
        Section {
            VStack(alignment: .leading) {
                chartHeader
                chartBody
            }
            .padding(25)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        }
        .listRowStyling()
    }
    
    private var chartHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Progress Over Time").font(.headline)
                if let selectedDataPoint, showChartValue {
                     Text("Top Speed on \(selectedDataPoint.date, formatter: .abbreviatedDate): \(String(format: "%.1f km/h", selectedDataPoint.topSpeed))")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text("Top Speed per Day (\(selectedRange.rawValue))").font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.bottom, 10)
    }
    
    @ViewBuilder
    private var chartBody: some View {
        let chartData = historyViewModel.aggregatedChartData
        
        if chartData.count > 1 {
            Chart(chartData) { dataPoint in
                LineMark(x: .value("Date", dataPoint.date, unit: .day), y: .value("Speed", dataPoint.topSpeed))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.8), .accentColor.opacity(0.2)], startPoint: .top, endPoint: .bottom))

                PointMark(x: .value("Date", dataPoint.date, unit: .day), y: .value("Speed", dataPoint.topSpeed))
                    .foregroundStyle(Color.accentColor)
            }
            .chartYScale(domain: 0...((historyViewModel.filteredTopSpeed > 0 ? historyViewModel.filteredTopSpeed : 250) * 1.2))
            .frame(height: 200)
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day()) } }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let location = value.location
                                    showChartValue = true
                                    if let date: Date = proxy.value(atX: location.x) {
                                         let closest = chartData.min(by: { abs($0.date.distance(to: date)) < abs($1.date.distance(to: date)) })
                                         if let closestDataPoint = closest { self.selectedDataPoint = closestDataPoint }
                                    }
                                }
                                .onEnded { _ in showChartValue = false }
                        )
                }
            }
        } else {
            Text("Not enough data with current filters to draw a chart.")
                .font(.subheadline).foregroundColor(.secondary).padding()
                .frame(height: 200, alignment: .center)
        }
    }
    
    /// View for the filter controls.
    private var filterControlsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 15) {
                Text("Filters").font(.headline)
                
                Picker("Time Range", selection: $selectedRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                
                Divider()
                
                Toggle(isOn: $speedFilterEnabled.animation()) {
                    Text("Filter by Speed")
                }
                
                if speedFilterEnabled {
                    VStack {
                        HStack {
                            Text("Min Speed:")
                            Spacer()
                            Text("\(Int(minimumSpeed)) km/h").bold()
                        }
                        Slider(value: $minimumSpeed, in: 50...400, step: 5)
                    }
                    .padding(.top, 5)
                }
            }
            .padding(20)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        }
        .listRowStyling()
    }
    
    /// View for the list of historical results.
    private var historyListSection: some View {
        Section(header: Text("History").padding(.leading)) {
            if historyViewModel.filteredResults.isEmpty {
                 Text("No results match your current filters.")
                     .foregroundColor(.secondary)
                     .padding()
                     .frame(maxWidth: .infinity, alignment: .center)
                     .listRowBackground(Color.clear)
                     .listRowSeparator(.hidden)
            } else {
                ForEach(historyViewModel.filteredResults) { result in
                    HistoryRow(result: result)
                        .padding()
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
                        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }
    
    /// View for when a user is logged out.
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

// MARK: - View Modifiers & Subviews

/// A custom view modifier to reduce code repetition for list row styling.
struct ListRowStyler: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
    }
}

extension View {
    func listRowStyling() -> some View {
        modifier(ListRowStyler())
    }
}

/// A view for a single row in the stats panel.
struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack { Text(label); Spacer(); Text(value).fontWeight(.bold).foregroundColor(.secondary) }
    }
}

/// A view for a single row in the history list.
struct HistoryRow: View {
    let result: DetectionResult
    
    var body: some View {
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
            NavigationLink(destination: ResultDetailView(result: result)) {
                rowContent
            }
        } else {
            rowContent
        }
    }
}

// MARK: - Detail View & ViewModel

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
        // Sort the frameData by timestamp to ensure it's in order for the table
        self.frameData = result.frameData?.sorted { $0.timestamp < $1.timestamp } ?? []
        
        Task {
            await loadVideoSize()
            startObserving()
        }
    }
    
    private func loadVideoSize() async {
        guard let track = try? await originalAsset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize) else { return }
        self.videoSize = size
    }
    
    func startObserving() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentTime = time.seconds
            
            if let currentFrame = self.frameData.min(by: { abs($0.timestamp - currentTime) < abs($1.timestamp - currentTime) }) {
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
                    
                    // Add the new timestamp table section here
                    timestampTableSection
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
                         .font(.callout).foregroundColor(.secondary)
                     Spacer()
                     Text(String(format: "%.0f° downward", angle))
                         .font(.callout).fontWeight(.semibold)
                 }
                 .padding(.horizontal)
             }

             HStack {
                 Text("Live Speed:")
                     .font(.callout).foregroundColor(.secondary)
                 Spacer()
                 Text(String(format: "%.1f km/h", viewModel.currentSpeed))
                     .font(.callout).fontWeight(.semibold)
             }
             .padding(.horizontal)
         }
         .padding(20)
         .background(GlassPanel())
         .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
    }
    
    // New view for the timestamp data table
    @ViewBuilder
    private var timestampTableSection: some View {
        if !viewModel.frameData.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Timestamp Data")
                    .font(.headline)
                    .padding([.horizontal, .top])
                
                // Table Header
                HStack {
                    Text("Time").fontWeight(.bold)
                    Spacer()
                    Text("Speed").fontWeight(.bold)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                
                Divider().padding(.horizontal)
                
                // Table Rows
                ForEach(viewModel.frameData, id: \.timestamp) { frame in
                    HStack {
                        Text(String(format: "%.2f s", frame.timestamp))
                        Spacer()
                        Text(String(format: "%.1f km/h", frame.speedKPH))
                    }
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal)
                    
                    Divider().padding(.horizontal)
                }
                .padding(.bottom, 5)
                
            }
            .padding(.vertical, 10)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
    }
}

// MARK: - History View Model
@MainActor
class HistoryViewModel: ObservableObject {
    @Published var allResults = [DetectionResult]()
    @Published var filteredResults = [DetectionResult]()
    @Published var aggregatedChartData = [DailyTopSpeed]()
    
    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    var filteredTopSpeed: Double { filteredResults.map { $0.peakSpeedKph }.max() ?? 0.0 }
    var filteredAverageSpeed: Double {
        let speeds = filteredResults.map { $0.peakSpeedKph }
        return speeds.isEmpty ? 0.0 : speeds.reduce(0, +) / Double(speeds.count)
    }
    var filteredDetectionCount: Int { filteredResults.count }
    
    func subscribe(to userID: String) {
        if listenerRegistration != nil { unsubscribe() }
        let query = db.collection("detections").whereField("userID", isEqualTo: userID).order(by: "date", descending: true)
        
        listenerRegistration = query.addSnapshotListener { [weak self] (snapshot, error) in
            guard let self = self, let docs = snapshot?.documents, error == nil else {
                #if DEBUG
                print("Error fetching snapshot: \(error?.localizedDescription ?? "Unknown error")")
                #endif
                return
            }
            self.allResults = docs.compactMap { try? $0.data(as: DetectionResult.self) }
        }
    }
    
    func applyFilters(range: TimeRange, speedFilterEnabled: Bool, minSpeed: Double) {
        let calendar = Calendar.current
        
        let timeFiltered: [DetectionResult]
        switch range {
        case .week:
            guard let targetDate = calendar.date(byAdding: .day, value: -7, to: Date()) else { return }
            timeFiltered = allResults.filter { $0.date.dateValue() >= calendar.startOfDay(for: targetDate) }
        case .month:
            guard let targetDate = calendar.date(byAdding: .month, value: -1, to: Date()) else { return }
            timeFiltered = allResults.filter { $0.date.dateValue() >= calendar.startOfDay(for: targetDate) }
        case .all:
            timeFiltered = allResults
        }
        
        let speedFiltered: [DetectionResult]
        if speedFilterEnabled {
            speedFiltered = timeFiltered.filter { $0.peakSpeedKph >= minSpeed }
        } else {
            speedFiltered = timeFiltered
        }
        
        self.filteredResults = speedFiltered
        updateChartData(from: speedFiltered)
    }
    
    private func updateChartData(from results: [DetectionResult]) {
        let calendar = Calendar.current
        
        let groupedByDay = Dictionary(grouping: results) { result in
            calendar.startOfDay(for: result.date.dateValue())
        }
        
        let dailyTopSpeeds = groupedByDay.compactMap { (date, dailyResults) -> DailyTopSpeed? in
            guard let topSpeed = dailyResults.map({ $0.peakSpeedKph }).max() else { return nil }
            return DailyTopSpeed(date: date, topSpeed: topSpeed)
        }
        
        self.aggregatedChartData = dailyTopSpeeds.sorted { $0.date < $1.date }
    }
    
    func unsubscribe() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        allResults = []
        filteredResults = []
        aggregatedChartData = []
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
}

// MARK: - DateFormatter Extension
extension Formatter {
    static let abbreviatedDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

extension Text {
     init(_ date: Date, formatter: DateFormatter) {
         self.init(formatter.string(from: date))
     }
}
