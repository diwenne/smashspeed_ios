//
//  HistoryView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//

import SwiftUI
import FirebaseFirestore
import Combine
import Charts
import FirebaseAuth // This import is now correctly used.

// MARK: - History Tab

struct HistoryView: View {
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @StateObject private var historyViewModel = HistoryViewModel()
    
    var body: some View {
        NavigationStack {
            VStack {
                // This 'if' statement will now compile correctly.
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
            .onDisappear {
                historyViewModel.unsubscribe()
            }
            // This .onChange modifier will also now compile correctly.
            .onChange(of: authViewModel.user) { _, newUser in
                if let userID = newUser?.uid {
                    historyViewModel.subscribe(to: userID)
                } else {
                    historyViewModel.unsubscribe()
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
                // Overall Stats Section
                Section(header: Text("Overall Stats")) {
                    StatRow(label: "Top Speed", value: String(format: "%.1f km/h", historyViewModel.topSpeed))
                    StatRow(label: "Average Speed", value: String(format: "%.1f km/h", historyViewModel.averageSpeed))
                    StatRow(label: "Total Smashes", value: "\(historyViewModel.detectionCount)")
                }
                
                // Progress Chart Section
                Section("Progress Over Time") {
                    if historyViewModel.detectionResults.count > 1 {
                        Chart {
                            ForEach(historyViewModel.detectionResults.reversed()) { result in
                                LineMark(
                                    x: .value("Date", result.date.dateValue(), unit: .day),
                                    y: .value("Speed", result.peakSpeedKph)
                                )
                                .interpolationMethod(.catmullRom)

                                PointMark(
                                    x: .value("Date", result.date.dateValue(), unit: .day),
                                    y: .value("Speed", result.peakSpeedKph)
                                )
                                .foregroundStyle(.blue)
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
                
                // Detailed History Section
                Section(header: Text("History")) {
                    ForEach(historyViewModel.detectionResults) { result in
                        HistoryRow(result: result)
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

struct HistoryRow: View {
    let result: DetectionResult
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(result.date.dateValue(), style: .date).font(.headline)
                Text(result.date.dateValue(), style: .time).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(result.formattedSpeed).font(.title2).fontWeight(.semibold)
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
            guard let docs = snapshot?.documents else { return }
            self?.detectionResults = docs.compactMap { try? $0.data(as: DetectionResult.self) }
        }
    }
    
    func unsubscribe() {
        listenerRegistration?.remove()
        listenerRegistration = nil
        detectionResults = []
    }
    
    static func saveResult(peakSpeedKph: Double, for userID: String) throws {
        let db = Firestore.firestore()
        let result = DetectionResult(userID: userID, date: Timestamp(date: Date()), peakSpeedKph: peakSpeedKph)
        try db.collection("detections").addDocument(from: result)
    }
    
    func deleteResult(at offsets: IndexSet) {
        let resultsToDelete = offsets.map { self.detectionResults[$0] }
        for result in resultsToDelete {
            guard let docID = result.id else { continue }
            db.collection("detections").document(docID).delete()
        }
    }
}

struct DetectionResult: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    let userID: String
    let date: Timestamp
    let peakSpeedKph: Double
    var formattedSpeed: String { String(format: "%.1f km/h", peakSpeedKph) }
}
