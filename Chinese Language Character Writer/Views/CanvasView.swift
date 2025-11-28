import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    let toolPicker: PKToolPicker
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 2)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        
        // Configure tool picker
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        toolPicker.addObserver(canvasView)
        canvasView.becomeFirstResponder()
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update the canvas view if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(canvasView: $canvasView)
    }
}

class Coordinator: NSObject, PKCanvasViewDelegate {
    @Binding var canvasView: PKCanvasView
    
    init(canvasView: Binding<PKCanvasView>) {
        self._canvasView = canvasView
    }
    
    // Add any delegate methods if needed
}
