import SwiftUI

struct ParameterOptimizationView: View {
    @ObservedObject var validator: StrokeMatchingValidator
    @StateObject private var optimizer = ParameterOptimizer()
    @Environment(\.dismiss) var dismiss
    @State private var selectedStrategy: SearchStrategy = .coarse
    @State private var showingAppliedAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                if optimizer.isOptimizing {
                    optimizingView
                } else if let result = optimizer.optimizationResult {
                    resultsView(result: result)
                } else {
                    startView
                }
            }
            .navigationTitle("Optimize Parameters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(optimizer.isOptimizing)
                }
            }
            .alert("Parameters Applied", isPresented: $showingAppliedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Optimized parameters have been applied to the validator.")
            }
        }
    }
    
    // MARK: - Start View
    
    private var startView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Auto-Tune Algorithm")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Automatically find the best parameter values to maximize accuracy on your validation dataset.")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Divider()
                    .padding(.vertical)
                
                // Strategy Selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("Search Strategy")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(SearchStrategy.allCases) { strategy in
                        Button {
                            selectedStrategy = strategy
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(strategy.rawValue)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(strategy.description)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                if selectedStrategy == strategy {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(selectedStrategy == strategy ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                
                Button(action: runOptimization) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Optimization")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Optimizing View
    
    private var optimizingView: some View {
        VStack(spacing: 24) {
            ProgressView(value: optimizer.progress) {
                Text(optimizer.currentTestDescription)
                    .font(.headline)
            }
            .progressViewStyle(.linear)
            .padding(.horizontal)
            
            Text("\(Int(optimizer.progress * 100))% Complete")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Text("This may take a while. Please be patient...")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Results View
    
    private func resultsView(result: OptimizationResult) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Best Parameters Card
                bestParametersCard(result: result)
                
                // Comparison with Default
                comparisonCard(result: result)
                
                // Top 5 Results
                topResultsSection(result: result)
                
                // Actions
                actionButtons(result: result)
            }
            .padding()
        }
    }
    
    private func bestParametersCard(result: OptimizationResult) -> some View {
        VStack(spacing: 16) {
            Text("🏆 Best Parameters Found")
                .font(.title2)
                .fontWeight(.bold)
            
            // Big accuracy number
            Text("\(Int(result.bestParameters.accuracy * 100))%")
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(.green)
            
            Text("Accuracy")
                .font(.headline)
                .foregroundColor(.gray)
            
            Divider()
            
            // Parameter values
            VStack(alignment: .leading, spacing: 12) {
                Text("Baseline Algorithm")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Fréchet distance + Optimal assignment")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .italic()
                
                Divider()
                
                ParameterRow(name: "Prior Sigma", value: result.bestParameters.priorSigma)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Text("Perfect Entry Rate: \(Int(result.bestParameters.perfectEntryRate * 100))%")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .gray.opacity(0.2), radius: 4)
    }
    
    private func comparisonCard(result: OptimizationResult) -> some View {
        VStack(spacing: 12) {
            Text("Improvement Over Default")
                .font(.headline)
            
            if result.improvementOverDefault > 0 {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.green)
                    Text("+\(String(format: "%.1f", result.improvementOverDefault * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            } else if result.improvementOverDefault < 0 {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.red)
                    Text("\(String(format: "%.1f", result.improvementOverDefault * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            } else {
                Text("No improvement")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
            
            Text("Tested \(result.totalCombinationsTested) combinations in \(String(format: "%.1f", result.duration)) seconds")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func topResultsSection(result: OptimizationResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top 5 Results")
                .font(.title3)
                .fontWeight(.bold)
            
            ForEach(Array(result.allResults.prefix(5))) { params in
                TopResultRow(params: params, rank: result.allResults.firstIndex(where: { $0.id == params.id })! + 1)
            }
        }
    }
    
    private func actionButtons(result: OptimizationResult) -> some View {
        VStack(spacing: 12) {
            Button {
                applyParameters(result.bestParameters)
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Apply These Parameters")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green)
                .cornerRadius(12)
            }
            
            Button {
                optimizer.optimizationResult = nil
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Run Again")
                }
                .font(.headline)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private func runOptimization() {
        Task {
            await optimizer.optimizeParameters(searchStrategy: selectedStrategy)
        }
    }
    
    private func applyParameters(_ params: ParameterSet) {
        // Apply the optimized parameters to the validator
        validator.priorSigma = params.priorSigma
        showingAppliedAlert = true
        
        // Dismiss after a short delay to show the alert
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
}

// MARK: - Parameter Row

struct ParameterRow: View {
    let name: String
    let value: Double
    
    var body: some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
            Text(String(format: "%.3f", value))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Top Result Row

struct TopResultRow: View {
    let params: ParameterSet
    let rank: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(rank)")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text("\(Int(params.accuracy * 100))%")
                    .font(.title3)
                    .fontWeight(.bold)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Prior Sigma: \(String(format: "%.2f", params.priorSigma))")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Algorithm: Fréchet distance + Optimal assignment")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .italic()
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}
