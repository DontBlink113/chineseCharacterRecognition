//
//  ContentView.swift
//  Chinese Language Character Writer
//
//  Created by Keane Haesle on 11/18/25.
//

import SwiftUI
import PencilKit

struct ContentView: View {
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Lined Paper Background
                LinedPaperView()
                    .edgesIgnoringSafeArea(.all)
                
                // Drawing Canvas with native tool picker
                CanvasView(canvasView: $canvasView, toolPicker: toolPicker)
            }
            .navigationTitle("Chinese Character Writer")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }
    }
}

struct LinedPaperView: View {
    var lineSpacing: CGFloat = 44 // Slightly larger for better touch targets
    var lineColor: Color = .gray.opacity(0.3)
    
    var body: some View {
        GeometryReader { geometry in
            let lineCount = Int(geometry.size.height / lineSpacing) + 1
            
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<lineCount, id: \.self) { _ in
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(lineColor)
                            .padding(.horizontal, 40)
                        Spacer()
                            .frame(height: lineSpacing - 1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .background(Color.white)
            }
        }
        .background(Color(UIColor.systemGray6))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
