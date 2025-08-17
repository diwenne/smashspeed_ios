import SwiftUI
import FirebaseFirestore
import Combine
import Charts
import FirebaseAuth
import AVKit
import FirebaseStorage
import CoreGraphics

// MARK: - Helper Types for History View
enum TimeRange: String, CaseIterable, Identifiable {
    case week = "Past Week"
    case month = "Past Month"
    case all = "All Time"
    var id: Self { self }

    var localizedKey: String {
        switch self {
        case .week: return "history_range_week"
        case .month: return "history_range_month"
        case .all: return "history_range_all"
        }
    }
}

struct DailyTopSpeed: Identifiable {
    let id = UUID()
    let date: Date
    let topSpeed: Double
}


// MARK: - Main History View
struct HistoryView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @StateObject private var historyViewModel = HistoryViewModel()
    
    @State private var selectedRange: TimeRange = .week
    @State private var speedFilterEnabled = false
    @State private var minimumSpeed: Double = 150.0
    
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
                .navigationTitle(Text("history_navTitle"))
                .onAppear {
                    if let userID = authViewModel.user?.uid {
                        historyViewModel.subscribe(to: userID)
                    }
                }
                .onChange(of: selectedRange) { _ in applyFilters() }
                .onChange(of: speedFilterEnabled) { _ in applyFilters() }
                .onChange(of: minimumSpeed) { _ in applyFilters() }
                .onChange(of: historyViewModel.allResults) { _ in applyFilters() }
                .alert(Text("history_alert_delete_title"), isPresented: $showDeleteConfirmation, presenting: resultToDelete) { result in
                    Button("common_delete", role: .destructive) {
                        historyViewModel.deleteResult(result)
                    }
                } message: { result in
                    Text("history_alert_delete_message")
                }
            }
        }
    }
    
    private func applyFilters() {
        historyViewModel.applyFilters(
            range: selectedRange,
            speedFilterEnabled: speedFilterEnabled,
            minSpeed: minimumSpeed
        )
    }
    
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

    private var emptyStateView: some View {
        VStack {
            ContentUnavailableView("history_empty_title", systemImage: "list.bullet.clipboard", description: Text("history_empty_message"))
        }
        .padding(40)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .padding()
    }
    
    private var statsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("history_stats_title").font(.headline).padding(.bottom, 5)
                StatRow(labelKey: "history_stats_topSpeed", value: String(format: "%.1f km/h", historyViewModel.filteredTopSpeed))
                Divider()
                StatRow(labelKey: "history_stats_avgSpeed", value: String(format: "%.1f km/h", historyViewModel.filteredAverageSpeed))
                Divider()
                StatRow(labelKey: "history_stats_totalSmashes", value: "\(historyViewModel.filteredDetectionCount)")
            }
            .padding(20)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        }
        .listRowStyling()
    }
    
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
                Text("history_chart_title").font(.headline)
                if let selectedDataPoint, showChartValue {
                    Text(String.localizedStringWithFormat(NSLocalizedString("history_chart_selectedDataFormat", comment: ""), selectedDataPoint.date.formatted(date: .abbreviated, time: .omitted), selectedDataPoint.topSpeed))
                       .font(.caption).foregroundColor(.secondary)
                } else {
                    Text(String.localizedStringWithFormat(NSLocalizedString("history_chart_subtitleFormat", comment: ""), NSLocalizedString(selectedRange.localizedKey, comment: "")))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.bottom, 10)
    }
    
    private var chartView: some View {
        let chartData = historyViewModel.aggregatedChartData
        
        return Chart(chartData) { dataPoint in
            LineMark(x: .value("Date", dataPoint.date, unit: .day), y: .value("Speed", dataPoint.topSpeed))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [.accentColor.opacity(0.8), .accentColor.opacity(0.2)], startPoint: .top, endPoint: .bottom))

            PointMark(x: .value("Date", dataPoint.date, unit: .day), y: .value("Speed", dataPoint.topSpeed))
                .foregroundStyle(Color.accentColor)
        }
        .chartYScale(domain: 0...((historyViewModel.filteredTopSpeed > 0 ? historyViewModel.filteredTopSpeed : 250) * 1.2))
        .frame(height: 200)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month().day(), centered: true)
            }
        }
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
    }

    @ViewBuilder
    private var chartBody: some View {
        if historyViewModel.aggregatedChartData.count > 1 {
            chartView
        } else {
            Text("history_chart_noData")
                .font(.subheadline).foregroundColor(.secondary).padding()
                .frame(height: 200, alignment: .center)
        }
    }
    
    private var filterControlsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 15) {
                Text("history_filters_title").font(.headline)
                
                HStack {
                    Text("history_filters_timeRange")
                        .font(.callout)
                    Spacer()
                    Menu {
                        Picker(selection: $selectedRange, label: EmptyView()) {
                            ForEach(TimeRange.allCases) { range in
                                Text(LocalizedStringKey(range.localizedKey)).tag(range)
                            }
                        }
                    } label: {
                        HStack {
                            Text(LocalizedStringKey(selectedRange.localizedKey))
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .font(.callout)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                Toggle(isOn: $speedFilterEnabled.animation()) {
                    Text("history_filters_filterBySpeed")
                }
                
                if speedFilterEnabled {
                    VStack {
                        HStack {
                            Text("history_filters_minSpeed")
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
    
    private var historyListSection: some View {
        Section(header: Text("history_list_title").padding(.leading)) {
            if historyViewModel.filteredResults.isEmpty {
                 Text("history_list_noResults")
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
                                Label("common_delete", systemImage: "trash.fill")
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
    
    private var loggedOutView: some View {
        VStack {
            ContentUnavailableView("history_loggedOut_title", systemImage: "person.crop.circle.badge.questionmark", description: Text("history_loggedOut_message"))
        }
        .padding(40)
        .background(GlassPanel())
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .padding()
    }
}

// MARK: - View Modifiers & Subviews

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

struct StatRow: View {
    let labelKey: LocalizedStringKey
    let value: String
    var body: some View { HStack { Text(labelKey); Spacer(); Text(value).fontWeight(.bold).foregroundColor(.secondary) } }
}

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
                    timestampTableSection
                }
                .padding()
            }
        }
        .navigationTitle(Text("details_navTitle"))
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
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 15) {
                Text("details_peakSpeed")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text(String(format: "%.1f km/h", result.peakSpeedKph))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Divider()

                if let angle = result.angle {
                    HStack {
                        Text("common_smashAngle")
                            .font(.callout).foregroundColor(.secondary)
                        Spacer()
                        Text(String.localizedStringWithFormat(NSLocalizedString("resultView_angleFormat", comment: ""), angle))
                            .font(.callout).fontWeight(.semibold)
                    }
                    .padding(.horizontal)
                }

                HStack {
                    Text("details_liveSpeed")
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

            Button(action: renderImageForSharing) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .padding(20)
                    .contentShape(Rectangle())
            }
            .tint(.blue)
        }
    }

    @MainActor
    private func renderImageForSharing() {
        let shareView = ShareableView(speed: result.peakSpeedKph, angle: result.angle)
        self.shareableImage = shareView.snapshot()
    }

    @ViewBuilder
    private var timestampTableSection: some View {
        if !viewModel.frameData.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("details_timestampTitle")
                    .font(.headline)
                    .padding([.horizontal, .top])
                
                HStack {
                    Text("details_timeHeader").fontWeight(.bold)
                    Spacer()
                    Text("details_speedHeader").fontWeight(.bold)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

                Divider().padding(.horizontal)

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
