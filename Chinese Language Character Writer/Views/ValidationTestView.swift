import SwiftUI

struct ValidationTestView: View {
    @StateObject private var validator = StrokeMatchingValidator()
    @Environment(\.dismiss) var dismiss
    @State private var showingSettings = false
    @State private var showingOptimizer = false
    
    var body: some View {
        NavigationView {
            ZStack {
                if validator.isValidating {
                    validatingView
                } else if let metrics = validator.metrics {
                    resultsView(metrics: metrics)
                } else {
                    startView
                }
            }
            .navigationTitle("Algorithm Validation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .disabled(validator.isValidating)
                }
            }
            .sheet(isPresented: $showingSettings) {
                ValidationSettingsSheet(validator: validator)
            }
            .sheet(isPresented: $showingOptimizer) {
                ParameterOptimizationView()
            }
        }
    }
    
    // MARK: - Start View
    
    private var startView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Test Your Algorithm")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Run your stroke matching algorithm against the validation dataset to measure its accuracy.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button(action: runValidation) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run Validation")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                
                Button {
                    showingOptimizer = true
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Auto-Tune Parameters")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Validating View
    
    private var validatingView: some View {
        VStack(spacing: 24) {
            ProgressView(value: validator.progress) {
                Text("Validating...")
                    .font(.headline)
            }
            .progressViewStyle(.linear)
            .padding(.horizontal)
            
            Text("\(Int(validator.progress * 100))% Complete")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Results View
    
    private func resultsView(metrics: ValidationMetrics) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overall Metrics Card
                overallMetricsCard(metrics: metrics)
                
                // Per-Character Breakdown
                perCharacterBreakdown(metrics: metrics)
                
                // Detailed Results
                detailedResultsSection()
                
                // Rerun Button
                Button(action: runValidation) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Run Again")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
    
    private func overallMetricsCard(metrics: ValidationMetrics) -> some View {
        VStack(spacing: 16) {
            Text("Overall Performance")
                .font(.title2)
                .fontWeight(.bold)
            
            // Big accuracy number
            Text("\(Int(metrics.overallAccuracy * 100))%")
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(accuracyColor(metrics.overallAccuracy))
            
            Text("Stroke Accuracy")
                .font(.headline)
                .foregroundColor(.gray)
            
            Divider()
            
            // Detailed stats
            HStack(spacing: 40) {
                VStack {
                    Text("\(metrics.totalEntries)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Entries")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                VStack {
                    Text("\(metrics.totalStrokes)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Strokes")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                VStack {
                    Text("\(Int(metrics.perfectEntryRate * 100))%")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Perfect")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            // Correct vs Incorrect
            HStack(spacing: 20) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(metrics.correctStrokes) correct")
                        .font(.subheadline)
                }
                
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("\(metrics.incorrectStrokes) incorrect")
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private func perCharacterBreakdown(metrics: ValidationMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-Character Breakdown")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ForEach(metrics.characterMetrics.values.sorted(by: { $0.character < $1.character }), id: \.character) { charMetric in
                CharacterMetricRow(metric: charMetric)
            }
        }
    }
    
    private func detailedResultsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Results")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)
            
            ForEach(validator.results.filter { !$0.isCorrect }) { result in
                NavigationLink(destination: ValidationResultDetailView(result: result)) {
                    IncorrectEntryRow(result: result)
                }
            }
            
            if validator.results.filter({ !$0.isCorrect }).isEmpty {
                Text("🎉 All entries matched perfectly!")
                    .font(.headline)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
    
    private func accuracyColor(_ accuracy: Double) -> Color {
        if accuracy >= 0.9 { return .green }
        if accuracy >= 0.7 { return .orange }
        return .red
    }
    
    private func runValidation() {
        Task {
            await validator.validateDataset()
        }
    }
}

// MARK: - Character Metric Row

struct CharacterMetricRow: View {
    let metric: CharacterMetrics
    
    var body: some View {
        HStack {
            Text(metric.character)
                .font(.title)
                .fontWeight(.bold)
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(Int(metric.accuracy * 100))%")
                        .font(.headline)
                        .foregroundColor(accuracyColor)
                    
                    Spacer()
                    
                    Text("\(metric.correctStrokes)/\(metric.totalStrokes) strokes")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                ProgressView(value: metric.accuracy)
                    .tint(accuracyColor)
                
                Text("\(metric.totalEntries) entries, \(metric.perfectEntries) perfect")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .gray.opacity(0.2), radius: 2)
        .padding(.horizontal)
    }
    
    private var accuracyColor: Color {
        if metric.accuracy >= 0.9 { return .green }
        if metric.accuracy >= 0.7 { return .orange }
        return .red
    }
}

// MARK: - Incorrect Entry Row

struct IncorrectEntryRow: View {
    let result: ValidationResult
    
    var body: some View {
        HStack {
            Text(result.entry.character)
                .font(.title)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(result.accuracy * 100))% accuracy")
                    .font(.headline)
                
                Text("\(result.incorrectCount) incorrect stroke\(result.incorrectCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

// MARK: - Validation Settings Sheet

struct ValidationSettingsSheet: View {
    @ObservedObject var validator: StrokeMatchingValidator
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Algorithm Parameters")) {
                    VStack(alignment: .leading) {
                        Text("Error Threshold: \(String(format: "%.2f", validator.errorThreshold))")
                        Slider(value: $validator.errorThreshold, in: 0.1...1.0, step: 0.05)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Distance Weight: \(String(format: "%.2f", validator.distanceWeight))")
                        Slider(value: $validator.distanceWeight, in: 0...1, step: 0.05)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Length Weight: \(String(format: "%.2f", validator.lengthWeight))")
                        Slider(value: $validator.lengthWeight, in: 0...1, step: 0.05)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Temperature: \(String(format: "%.2f", validator.temperature))")
                        Slider(value: $validator.temperature, in: 0.01...1.0, step: 0.01)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Prior Sigma: \(String(format: "%.2f", validator.priorSigma))")
                        Slider(value: $validator.priorSigma, in: 0.5...5.0, step: 0.1)
                    }
                }
                
                Section {
                    Button("Reset to Defaults") {
                        validator.errorThreshold = 0.5
                        validator.distanceWeight = 0.7
                        validator.lengthWeight = 0.3
                        validator.temperature = 0.1
                        validator.priorSigma = 2.0
                    }
                }
            }
            .navigationTitle("Algorithm Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Validation Result Detail View

struct ValidationResultDetailView: View {
    let result: ValidationResult
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text(result.entry.character)
                        .font(.system(size: 60))
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("\(Int(result.accuracy * 100))%")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Accuracy")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                
                Divider()
                
                // Stroke-by-stroke comparison
                Text("Stroke Comparison")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                ForEach(result.strokeComparisons, id: \.strokeIndex) { comparison in
                    StrokeComparisonRow(comparison: comparison)
                }
            }
        }
        .navigationTitle("Validation Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StrokeComparisonRow: View {
    let comparison: (strokeIndex: Int, predicted: Int?, actual: Int?, isCorrect: Bool)
    
    var body: some View {
        HStack {
            // Stroke number
            Text("Stroke \(comparison.strokeIndex + 1)")
                .font(.headline)
                .frame(width: 100, alignment: .leading)
            
            // Predicted
            VStack(alignment: .leading) {
                Text("Predicted")
                    .font(.caption)
                    .foregroundColor(.gray)
                if let predicted = comparison.predicted {
                    Text("R\(predicted + 1)")
                        .font(.headline)
                } else {
                    Text("No Match")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 80)
            
            // Arrow
            Image(systemName: comparison.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(comparison.isCorrect ? .green : .red)
            
            // Actual
            VStack(alignment: .leading) {
                Text("Actual")
                    .font(.caption)
                    .foregroundColor(.gray)
                if let actual = comparison.actual {
                    Text("R\(actual + 1)")
                        .font(.headline)
                } else {
                    Text("No Match")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 80)
            
            Spacer()
        }
        .padding()
        .background(comparison.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
