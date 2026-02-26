import SwiftUI
import UIKit
import QuartzCore
import FSRS

// MARK: - Shared Stroke Rendering Utilities

/// Single source of truth for variable-width stroke geometry.
/// Previously copy-pasted into 4+ locations.
enum VariableStrokeStyle {
    static func width(
        pressure: CGFloat,
        speed: CGFloat,
        isNonPencil: Bool,
        speedSensitivity: Double,
        pressureSensitivity: Double,
        sizeFactor: Double
    ) -> CGFloat {
        let minW: CGFloat = 8.0 * CGFloat(sizeFactor)
        let maxW: CGFloat = 28.0 * CGFloat(sizeFactor)
        let v0: CGFloat = 1500.0 / max(0.1, CGFloat(speedSensitivity))
        let factor = 1.0 / (1.0 + max(0, speed) / v0)
        let pEff = max(0, min(1, pressure * CGFloat(pressureSensitivity)))
        let base = minW + (maxW - minW) * pEff * factor
        return base * (isNonPencil ? 0.5 : 1.0)
    }

    /// Smoothed width using exponential moving average over previous segment.
    static func smoothed(_ newWidth: CGFloat, previous: CGFloat) -> CGFloat {
        previous > 0 ? 0.7 * previous + 0.3 * newWidth : newWidth
    }
}

// MARK: - Single source-of-truth SVG parser
/// Previously duplicated in ReferenceStrokeShapeView, ReferenceMaskAnimationContainerView,
/// SVGMaskRevealContainerView, and FlashcardPracticeView.
enum SVGParser {
    enum Segment {
        case moveTo(CGPoint)
        case lineTo(CGPoint)
        case quadCurve(control: CGPoint, end: CGPoint)
        case cubicCurve(control1: CGPoint, control2: CGPoint, end: CGPoint)
        case closePath
    }

    static func parse(_ svgPath: String) -> [Segment] {
        var segments: [Segment] = []
        let parts = svgPath.split(separator: " ")
        var i = parts.startIndex

        func advance(_ n: Int) { i = parts.index(i, offsetBy: n) }
        func num(_ offset: Int) -> Double? { Double(parts[parts.index(i, offsetBy: offset)]) }

        while i < parts.endIndex {
            switch String(parts[i]) {
            case "M":
                guard let x = num(1), let y = num(2) else { advance(1); continue }
                segments.append(.moveTo(CGPoint(x: x, y: y))); advance(3)
            case "L":
                guard let x = num(1), let y = num(2) else { advance(1); continue }
                segments.append(.lineTo(CGPoint(x: x, y: y))); advance(3)
            case "Q":
                guard let x1 = num(1), let y1 = num(2), let x = num(3), let y = num(4)
                else { advance(1); continue }
                segments.append(.quadCurve(control: CGPoint(x: x1, y: y1), end: CGPoint(x: x, y: y)))
                advance(5)
            case "C":
                guard let x1 = num(1), let y1 = num(2), let x2 = num(3),
                      let y2 = num(4), let x = num(5), let y = num(6)
                else { advance(1); continue }
                segments.append(.cubicCurve(
                    control1: CGPoint(x: x1, y: y1),
                    control2: CGPoint(x: x2, y: y2),
                    end: CGPoint(x: x, y: y)))
                advance(7)
            case "Z", "z":
                segments.append(.closePath); advance(1)
            default:
                advance(1)
            }
        }
        return segments
    }

    /// Scale a normalised [0,1] SVG point into canvas space with a 10% inset on each side.
    static func scaleWithInset(_ point: CGPoint, canvasSize: CGFloat) -> CGPoint {
        let inset: CGFloat = 0.10
        let scale: CGFloat = 1.0 - inset * 2.0
        return CGPoint(
            x: (point.x * scale + inset) * canvasSize,
            y: (point.y * scale + inset) * canvasSize
        )
    }

    static func bezierPath(from svgPath: String, canvasSize: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for seg in parse(svgPath) {
            switch seg {
            case .moveTo(let p):   path.move(to: scaleWithInset(p, canvasSize: canvasSize))
            case .lineTo(let p):   path.addLine(to: scaleWithInset(p, canvasSize: canvasSize))
            case .quadCurve(let c, let e):
                path.addQuadCurve(to: scaleWithInset(e, canvasSize: canvasSize),
                                  controlPoint: scaleWithInset(c, canvasSize: canvasSize))
            case .cubicCurve(let c1, let c2, let e):
                path.addCurve(to: scaleWithInset(e, canvasSize: canvasSize),
                              controlPoint1: scaleWithInset(c1, canvasSize: canvasSize),
                              controlPoint2: scaleWithInset(c2, canvasSize: canvasSize))
            case .closePath:
                path.close()
            }
        }
        return path
    }

    /// SwiftUI Path variant (used by ReferenceStrokeShapeView).
    static func swiftUIPath(from svgPath: String, canvasSize: CGFloat) -> Path {
        var path = Path()
        for seg in parse(svgPath) {
            switch seg {
            case .moveTo(let p):   path.move(to: scaleWithInset(p, canvasSize: canvasSize))
            case .lineTo(let p):   path.addLine(to: scaleWithInset(p, canvasSize: canvasSize))
            case .quadCurve(let c, let e):
                path.addQuadCurve(to: scaleWithInset(e, canvasSize: canvasSize),
                                  control: scaleWithInset(c, canvasSize: canvasSize))
            case .cubicCurve(let c1, let c2, let e):
                path.addCurve(to: scaleWithInset(e, canvasSize: canvasSize),
                              control1: scaleWithInset(c1, canvasSize: canvasSize),
                              control2: scaleWithInset(c2, canvasSize: canvasSize))
            case .closePath:
                path.closeSubpath()
            }
        }
        return path
    }

    /// Parse character to get reference strokes using StrokeAnalyzer
    static func parseCharacter(_ character: String) -> [ReferenceStroke] {
        let graphicsData = StrokeAnalyzer.loadGraphicsData()
        guard let refChar = graphicsData[character] else { return [] }
        return StrokeAnalyzer.normalizeReferenceStrokes(refChar.medians, svgPaths: refChar.strokes)
    }
}

// MARK: - VariableWidthStrokeView

struct VariableWidthStrokeView: View {
    let stroke: Stroke
    let color: Color
    let speedSensitivity: Double
    let pressureSensitivity: Double
    let sizeFactor: Double

    var body: some View {
        Canvas { context, _ in
            let pts = stroke.displayPoints
            guard !pts.isEmpty else { return }
            let isNonPencil = pts.allSatisfy { $0.pressure >= 0.999 }

            func w(_ a: StrokePoint, _ b: StrokePoint) -> CGFloat {
                VariableStrokeStyle.width(
                    pressure: (a.pressure + b.pressure) * 0.5,
                    speed: max(0.001, (a.speed + b.speed) * 0.5),
                    isNonPencil: isNonPencil,
                    speedSensitivity: speedSensitivity,
                    pressureSensitivity: pressureSensitivity,
                    sizeFactor: sizeFactor
                )
            }

            if pts.count == 1 {
                let raw = VariableStrokeStyle.width(pressure: pts[0].pressure, speed: pts[0].speed,
                                            isNonPencil: isNonPencil,
                                            speedSensitivity: speedSensitivity,
                                            pressureSensitivity: pressureSensitivity,
                                            sizeFactor: sizeFactor)
                let p = pts[0].location
                context.fill(
                    Path(ellipseIn: CGRect(x: p.x - raw/2, y: p.y - raw/2, width: raw, height: raw)),
                    with: .color(color))
                return
            }

            var prevW: CGFloat = 0
            for i in 1..<pts.count {
                let p0 = pts[i-1].location
                let p1 = pts[i].location
                var segW = w(pts[i-1], pts[i])
                segW = VariableStrokeStyle.smoothed(segW, previous: prevW)
                prevW = segW

                var seg = Path()
                seg.move(to: p0)
                seg.addLine(to: p1)
                context.stroke(seg, with: .color(color),
                               style: .init(lineWidth: segW, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - TouchCaptureView

struct TouchCaptureView: UIViewRepresentable {
    var onBegan: (CGPoint, CGFloat) -> Void
    var onMoved: (CGPoint, CGFloat) -> Void
    var onEnded: () -> Void
    var drawingBounds: CGRect?

    func makeUIView(context: Context) -> _TouchView { _TouchView(owner: self) }
    func updateUIView(_ uiView: _TouchView, context: Context) { uiView.owner = self }

    // Prefixed with _ so it stays internal; callers only see TouchCaptureView.
    final class _TouchView: UIView {
        var owner: TouchCaptureView
        private var active = false

        init(owner: TouchCaptureView) {
            self.owner = owner
            super.init(frame: .zero)
            isMultipleTouchEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError() }

        private func pressure(from touch: UITouch) -> CGFloat {
            touch.type == .pencil && touch.maximumPossibleForce > 0
                ? max(0, min(1, touch.force / touch.maximumPossibleForce))
                : 1.0
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            let loc = t.location(in: self)
            if let bounds = owner.drawingBounds, !bounds.contains(loc) {
                next?.touchesBegan(touches, with: event); return
            }
            active = true
            owner.onBegan(loc, pressure(from: t))
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first, active else { return }
            owner.onMoved(t.location(in: self), pressure(from: t))
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard active else { return }
            active = false
            owner.onEnded()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard active else { return }
            active = false
            owner.onEnded()
        }

        // Block scroll gestures that start inside the drawing area.
        override func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
            guard let pan = gr as? UIPanGestureRecognizer,
                  let bounds = owner.drawingBounds else { return true }
            return !bounds.contains(pan.location(in: self))
        }
    }
}

// MARK: - ReferenceStrokeShapeView

struct ReferenceStrokeShapeView: Shape {
    let referenceStroke: ReferenceStroke
    let canvasSize: CGFloat

    func path(in rect: CGRect) -> Path {
        SVGParser.swiftUIPath(from: referenceStroke.svgPath, canvasSize: canvasSize)
    }
}

// MARK: - CALayer-based mask-reveal animation
//
// Key performance fix: instead of one CAShapeLayer per stroke *segment* (potentially
// 200 layers per stroke), we render the entire variable-width stroke into a single
// CGImage and use that as the outline layer's contents. The mask is still a single
// CAShapeLayer animating strokeEnd along the median path.

final class MaskRevealContainerView: UIView {

    // MARK: Cached state
    private var builtNonce: Int = -1
    private var builtRefCount: Int = 0
    private var builtUserCount: Int = 0
    private var isPaused = false

    // Per-stroke layers (one pair per reference stroke)
    private var outlineLayers: [CALayer] = []
    private var maskLayers:   [CAShapeLayer] = []

    // MARK: Public entry point

    struct Config {
        var referenceStrokes: [ReferenceStroke]
        var userStrokes:      [Stroke]
        var strokeResults:    [StrokeAnalysisResult]
        var originalCanvasSize: CGFloat
        var boundingBox:      CGRect?
        var canvasSize:       CGFloat
        var totalDuration:    Double
        var replayNonce:      Int
        var pause:            Bool
        var speedSensitivity:    Double
        var pressureSensitivity: Double
        var sizeFactor:          Double
    }

    func configure(_ cfg: Config) {
        guard !cfg.referenceStrokes.isEmpty else { return }

        // Pause / resume without rebuilding
        handlePauseChange(cfg.pause)

        // Build reverse map: refIndex → matched userStroke index
        let refToUser: [Int: Int] = cfg.strokeResults.enumerated().reduce(into: [:]) { map, pair in
            let (uIdx, result) = pair
            if result.isMatched, let refIdx = result.bestMatchIndex { map[refIdx] = uIdx }
        }

        let needsRebuild = builtNonce    != cfg.replayNonce
                        || builtRefCount != cfg.referenceStrokes.count
                        || builtUserCount != cfg.userStrokes.count

        if !needsRebuild {
            updateLayersInPlace(cfg: cfg, refToUser: refToUser)
            return
        }

        rebuild(cfg: cfg, refToUser: refToUser)
    }

    // MARK: Private helpers

    private func handlePauseChange(_ shouldPause: Bool) {
        if shouldPause && !isPaused {
            let t = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0; layer.timeOffset = t; isPaused = true
        } else if !shouldPause && isPaused {
            let offset = layer.timeOffset
            layer.speed = 1; layer.timeOffset = 0; layer.beginTime = 0
            let drift = layer.convertTime(CACurrentMediaTime(), from: nil) - offset
            layer.beginTime = drift; isPaused = false
        }
    }

    private func updateLayersInPlace(cfg: Config, refToUser: [Int: Int]) {
        guard outlineLayers.count == cfg.referenceStrokes.count else { return }

        for (refIdx, ref) in cfg.referenceStrokes.enumerated() {
            guard refIdx < outlineLayers.count,
                  refIdx < maskLayers.count else { continue }
            let outlineLayer = outlineLayers[refIdx]
            let maskLayer = maskLayers[refIdx]

            if let uIdx = refToUser[refIdx], uIdx < cfg.userStrokes.count {
                // Replace contents with freshly-rendered user stroke image
                let color = strokeColor(refIdx: refIdx, userIdx: uIdx, results: cfg.strokeResults)
                let img = renderUserStroke(cfg.userStrokes[uIdx],
                                           canvasSize: cfg.canvasSize,
                                           bbox: cfg.boundingBox,
                                           color: color,
                                           speedSensitivity: cfg.speedSensitivity,
                                           pressureSensitivity: cfg.pressureSensitivity,
                                           sizeFactor: cfg.sizeFactor)
                outlineLayer.contents = img
                outlineLayer.frame = CGRect(origin: .zero, size: CGSize(width: cfg.canvasSize, height: cfg.canvasSize))

                // Mask follows user median path
                let userPath = userMedianPath(cfg.userStrokes[uIdx],
                                              canvasSize: cfg.canvasSize,
                                              bbox: cfg.boundingBox)
                maskLayer.path = userPath.cgPath
                maskLayer.lineWidth = userMaskWidth(canvasSize: cfg.canvasSize,
                                                    bbox: cfg.boundingBox,
                                                    sizeFactor: cfg.sizeFactor)
            } else {
                // Revert to reference outline
                let img = renderSVGOutline(ref.svgPath, canvasSize: cfg.canvasSize)
                outlineLayer.contents = img
                maskLayer.path = medianPath(ref.medianPoints, canvasSize: cfg.canvasSize).cgPath
                maskLayer.lineWidth = referenceMaskWidth(ref: ref, canvasSize: cfg.canvasSize)
            }
        }
    }

    private func rebuild(cfg: Config, refToUser: [Int: Int]) {
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        outlineLayers.removeAll(); maskLayers.removeAll()

        let count = cfg.referenceStrokes.count
        let perStroke = max(0.05, cfg.totalDuration / Double(count))
        let base = layer.convertTime(CACurrentMediaTime(), from: nil)

        for (refIdx, ref) in cfg.referenceStrokes.enumerated() {
            // 1. Outline — rendered as a flat CGImage (no per-segment layer explosion)
            let outlineLayer = CALayer()
            outlineLayer.frame = CGRect(origin: .zero,
                                        size: CGSize(width: cfg.canvasSize, height: cfg.canvasSize))
            outlineLayer.contentsScale = UIScreen.main.scale

            if let uIdx = refToUser[refIdx], uIdx < cfg.userStrokes.count {
                let color = strokeColor(refIdx: refIdx, userIdx: uIdx, results: cfg.strokeResults)
                outlineLayer.contents = renderUserStroke(cfg.userStrokes[uIdx],
                                                          canvasSize: cfg.canvasSize,
                                                          bbox: cfg.boundingBox,
                                                          color: color,
                                                          speedSensitivity: cfg.speedSensitivity,
                                                          pressureSensitivity: cfg.pressureSensitivity,
                                                          sizeFactor: cfg.sizeFactor)
            } else {
                outlineLayer.contents = renderSVGOutline(ref.svgPath, canvasSize: cfg.canvasSize)
            }

            // 2. Mask — single CAShapeLayer on the median path
            let maskLayer = CAShapeLayer()
            maskLayer.frame = outlineLayer.bounds
            maskLayer.contentsScale = UIScreen.main.scale
            maskLayer.strokeColor = UIColor.black.cgColor
            maskLayer.fillColor   = UIColor.clear.cgColor
            maskLayer.lineCap     = .round
            maskLayer.lineJoin    = .round
            maskLayer.strokeEnd   = 0

            if let uIdx = refToUser[refIdx], uIdx < cfg.userStrokes.count {
                maskLayer.path = userMedianPath(cfg.userStrokes[uIdx],
                                                 canvasSize: cfg.canvasSize,
                                                 bbox: cfg.boundingBox).cgPath
                maskLayer.lineWidth = userMaskWidth(canvasSize: cfg.canvasSize,
                                                    bbox: cfg.boundingBox,
                                                    sizeFactor: cfg.sizeFactor)
            } else {
                maskLayer.path = medianPath(ref.medianPoints, canvasSize: cfg.canvasSize).cgPath
                maskLayer.lineWidth = referenceMaskWidth(ref: ref, canvasSize: cfg.canvasSize)
            }

            outlineLayer.mask = maskLayer
            layer.addSublayer(outlineLayer)
            outlineLayers.append(outlineLayer)
            maskLayers.append(maskLayer)

            // 3. Animate strokeEnd
            let anim            = CABasicAnimation(keyPath: "strokeEnd")
            anim.fromValue      = 0
            anim.toValue        = 1
            anim.duration       = perStroke
            anim.beginTime      = base + Double(refIdx) * perStroke
            anim.timingFunction = CAMediaTimingFunction(name: .linear)
            anim.fillMode       = .forwards
            anim.isRemovedOnCompletion = false
            maskLayer.add(anim, forKey: "reveal")
        }

        if isPaused {
            let t = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0; layer.timeOffset = t
        }

        builtNonce     = cfg.replayNonce
        builtRefCount  = cfg.referenceStrokes.count
        builtUserCount = cfg.userStrokes.count
    }

    // MARK: Rendering helpers (CGImage, no extra layers)

    /// Renders a user stroke as a CGImage using CoreGraphics — O(n points), not O(n layers).
    private func renderUserStroke(
        _ stroke: Stroke, canvasSize: CGFloat, bbox: CGRect?,
        color: UIColor,
        speedSensitivity: Double, pressureSensitivity: Double, sizeFactor: Double
    ) -> CGImage? {
        let size = CGSize(width: canvasSize, height: canvasSize)
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        ctx.setLineCap(.round); ctx.setLineJoin(.round)

        let pts = stroke.displayPoints
        guard pts.count >= 2 else {
            // Single dot
            if let p = pts.first {
                let mapped = mapPoint(p.location, canvasSize: canvasSize, bbox: bbox)
                let r = VariableStrokeStyle.width(pressure: p.pressure, speed: p.speed,
                                          isNonPencil: false,
                                          speedSensitivity: speedSensitivity,
                                          pressureSensitivity: pressureSensitivity,
                                          sizeFactor: sizeFactor) * 0.5
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: CGRect(x: mapped.x - r, y: mapped.y - r,
                                           width: r*2, height: r*2))
            }
            return UIGraphicsGetCurrentContext().flatMap { _ in UIGraphicsGetImageFromCurrentImageContext()?.cgImage }
        }

        let isNonPencil = pts.allSatisfy { $0.pressure >= 0.999 }
        ctx.setStrokeColor(color.cgColor)
        var prevW: CGFloat = 0

        for i in 1..<pts.count {
            let a = pts[i-1], b = pts[i]
            var w = VariableStrokeStyle.width(
                pressure: (a.pressure + b.pressure) * 0.5,
                speed: max(0.001, (a.speed + b.speed) * 0.5),
                isNonPencil: isNonPencil,
                speedSensitivity: speedSensitivity,
                pressureSensitivity: pressureSensitivity,
                sizeFactor: sizeFactor)
            w = VariableStrokeStyle.smoothed(w, previous: prevW); prevW = w

            let pa = mapPoint(a.location, canvasSize: canvasSize, bbox: bbox)
            let pb = mapPoint(b.location, canvasSize: canvasSize, bbox: bbox)
            ctx.setLineWidth(w)
            ctx.move(to: pa); ctx.addLine(to: pb)
            ctx.strokePath()
        }
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }

    /// Renders an SVG filled outline as a CGImage.
    private func renderSVGOutline(_ svgPath: String, canvasSize: CGFloat) -> CGImage? {
        let size = CGSize(width: canvasSize, height: canvasSize)
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        let path = SVGParser.bezierPath(from: svgPath, canvasSize: canvasSize)
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }

    // MARK: Geometry helpers

    private func mapPoint(_ pt: CGPoint, canvasSize: CGFloat, bbox: CGRect?) -> CGPoint {
        guard let bb = bbox, bb.width > 0, bb.height > 0 else {
            return CGPoint(x: pt.x * canvasSize, y: pt.y * canvasSize)
        }
        return CGPoint(
            x: (pt.x - bb.minX) / bb.width  * canvasSize,
            y: (pt.y - bb.minY) / bb.height * canvasSize
        )
    }

    private func userMedianPath(_ stroke: Stroke, canvasSize: CGFloat, bbox: CGRect?) -> UIBezierPath {
        let pts = stroke.displayPoints.map { $0.location }
        let path = UIBezierPath()
        guard !pts.isEmpty else { return path }
        let mapped = pts.map { mapPoint($0, canvasSize: canvasSize, bbox: bbox) }
        path.move(to: mapped[0])
        mapped.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    private func medianPath(_ points: [CGPoint], canvasSize: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        guard !points.isEmpty else { return path }
        let scaled = points.map { SVGParser.scaleWithInset($0, canvasSize: canvasSize) }
        path.move(to: scaled[0])
        scaled.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }

    private func userMaskWidth(canvasSize: CGFloat, bbox: CGRect?, sizeFactor: Double) -> CGFloat {
        let maxUserW: CGFloat = 28.0 * CGFloat(sizeFactor)
        if let bb = bbox, bb.width > 0, bb.height > 0 {
            let scale = canvasSize / max(bb.width, bb.height)
            return max(1, maxUserW * scale * 2.2)
        }
        return max(12, canvasSize * 0.08)
    }

    private func referenceMaskWidth(ref: ReferenceStroke, canvasSize: CGFloat) -> CGFloat {
        let outline  = SVGParser.bezierPath(from: ref.svgPath, canvasSize: canvasSize).bounds
        let medianPt = medianPath(ref.medianPoints, canvasSize: canvasSize).bounds
        let estimated = max(outline.width - medianPt.width, outline.height - medianPt.height)
        let fallback  = max(canvasSize * 0.10, max(outline.width, outline.height) * 0.5)
        return max(estimated * 1.5, fallback)
    }

    private func strokeColor(refIdx: Int, userIdx: Int,
                              results: [StrokeAnalysisResult]) -> UIColor {
        guard userIdx < results.count,
              let matched = results[userIdx].bestMatchIndex else { return .systemRed }
        return matched == refIdx ? .systemGreen : .systemYellow
    }
}

// MARK: - SwiftUI wrapper for MaskRevealContainerView

struct ReferenceStrokeMaskAnimationView: UIViewRepresentable {
    let referenceStrokes:    [ReferenceStroke]
    let userStrokes:         [Stroke]
    let strokeResults:       [StrokeAnalysisResult]
    let originalCanvasSize:  CGFloat
    let boundingBox:         CGRect?
    let canvasSize:          CGFloat
    let totalDuration:       Double
    let replayNonce:         Int
    let pause:               Bool
    let speedSensitivity:    Double
    let pressureSensitivity: Double
    let sizeFactor:          Double

    func makeUIView(context: Context) -> MaskRevealContainerView {
        let v = MaskRevealContainerView()
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: MaskRevealContainerView, context: Context) {
        uiView.configure(MaskRevealContainerView.Config(
            referenceStrokes:    referenceStrokes,
            userStrokes:         userStrokes,
            strokeResults:       strokeResults,
            originalCanvasSize:  originalCanvasSize,
            boundingBox:         boundingBox,
            canvasSize:          canvasSize,
            totalDuration:       totalDuration,
            replayNonce:         replayNonce,
            pause:               pause,
            speedSensitivity:    speedSensitivity,
            pressureSensitivity: pressureSensitivity,
            sizeFactor:          sizeFactor
        ))
    }
}

// MARK: - SVGMaskRevealAnimationView (reference-only, no user strokes)

final class SVGRevealContainerView: UIView {
    private var prevNonce = -1
    private var maskLayers: [CAShapeLayer] = []

    func renderAndAnimate(referenceStrokes: [ReferenceStroke], canvasSize: CGFloat,
                          totalDuration: Double, replayNonce: Int) {
        guard !referenceStrokes.isEmpty, replayNonce != prevNonce else { return }
        prevNonce = replayNonce
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        maskLayers.removeAll()

        let per = totalDuration / Double(referenceStrokes.count)

        for (idx, ref) in referenceStrokes.enumerated() {
            let outlineLayer = CAShapeLayer()
            outlineLayer.path      = SVGParser.bezierPath(from: ref.svgPath, canvasSize: canvasSize).cgPath
            outlineLayer.fillColor = UIColor.black.cgColor

            let mPath  = UIBezierPath()
            let scaled = ref.medianPoints.map { SVGParser.scaleWithInset($0, canvasSize: canvasSize) }
            if let first = scaled.first {
                mPath.move(to: first)
                scaled.dropFirst().forEach { mPath.addLine(to: $0) }
            }
            let maskLayer = CAShapeLayer()
            maskLayer.path        = mPath.cgPath
            maskLayer.strokeColor = UIColor.black.cgColor
            maskLayer.fillColor   = UIColor.clear.cgColor
            maskLayer.lineWidth   = max(canvasSize * 0.08, 12)
            maskLayer.lineCap     = .round
            maskLayer.strokeEnd   = 0
            outlineLayer.mask     = maskLayer

            layer.addSublayer(outlineLayer)
            maskLayers.append(maskLayer)

            let anim = CABasicAnimation(keyPath: "strokeEnd")
            anim.fromValue = 0; anim.toValue = 1
            anim.duration  = per
            anim.beginTime = CACurrentMediaTime() + Double(idx) * per
            anim.fillMode  = .forwards
            anim.isRemovedOnCompletion = false
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            maskLayer.add(anim, forKey: "reveal")
        }
    }
}

struct SVGMaskRevealAnimationView: UIViewRepresentable {
    let referenceStrokes: [ReferenceStroke]
    let canvasSize:       CGFloat
    let totalDuration:    Double
    let replayNonce:      Int

    func makeUIView(context: Context) -> SVGRevealContainerView {
        let v = SVGRevealContainerView(); v.backgroundColor = .clear; return v
    }
    func updateUIView(_ v: SVGRevealContainerView, context: Context) {
        v.renderAndAnimate(referenceStrokes: referenceStrokes, canvasSize: canvasSize,
                           totalDuration: totalDuration, replayNonce: replayNonce)
    }
}

// MARK: - UserStrokesMaskRevealAnimationView

final class UserRevealContainerView: UIView {
    private var prevNonce = -1

    func renderAndAnimate(strokes: [Stroke], canvasSize: CGFloat, sourceCanvasSize: CGFloat,
                          totalDuration: Double, replayNonce: Int,
                          speedSensitivity: Double, pressureSensitivity: Double, sizeFactor: Double) {
        guard !strokes.isEmpty, replayNonce != prevNonce else { return }
        prevNonce = replayNonce
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let per   = totalDuration / Double(strokes.count)
        let scale = canvasSize / max(1, sourceCanvasSize)

        for (idx, stroke) in strokes.enumerated() {
            let pts = stroke.displayPoints
            guard pts.count >= 2 else { continue }

            // Render stroke as a CGImage
            let size = CGSize(width: canvasSize, height: canvasSize)
            UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
            if let ctx = UIGraphicsGetCurrentContext() {
                ctx.setLineCap(.round); ctx.setLineJoin(.round)
                let isNonPencil = pts.allSatisfy { $0.pressure >= 0.999 }
                ctx.setStrokeColor(UIColor.black.cgColor)
                var prevW: CGFloat = 0
                for i in 1..<pts.count {
                    let a = pts[i-1], b = pts[i]
                    var w = VariableStrokeStyle.width(
                        pressure: (a.pressure + b.pressure) * 0.5,
                        speed: max(0.001, (a.speed + b.speed) * 0.5),
                        isNonPencil: isNonPencil,
                        speedSensitivity: speedSensitivity,
                        pressureSensitivity: pressureSensitivity,
                        sizeFactor: sizeFactor)
                    w = VariableStrokeStyle.smoothed(w, previous: prevW) * scale
                    prevW = w
                    ctx.setLineWidth(w)
                    ctx.move(to: CGPoint(x: a.location.x * scale, y: a.location.y * scale))
                    ctx.addLine(to: CGPoint(x: b.location.x * scale, y: b.location.y * scale))
                    ctx.strokePath()
                }
            }
            let image = UIGraphicsGetImageFromCurrentImageContext()?.cgImage
            UIGraphicsEndImageContext()

            let outlineLayer = CALayer()
            outlineLayer.frame    = CGRect(origin: .zero, size: size)
            outlineLayer.contents = image
            outlineLayer.contentsScale = UIScreen.main.scale

            let medianPath = UIBezierPath()
            let mpts = pts.map { CGPoint(x: $0.location.x * scale, y: $0.location.y * scale) }
            medianPath.move(to: mpts[0])
            mpts.dropFirst().forEach { medianPath.addLine(to: $0) }

            let maskLayer = CAShapeLayer()
            maskLayer.path        = medianPath.cgPath
            maskLayer.strokeColor = UIColor.black.cgColor
            maskLayer.fillColor   = UIColor.clear.cgColor
            maskLayer.lineWidth   = max(12, canvasSize * 0.08)
            maskLayer.lineCap     = .round
            maskLayer.strokeEnd   = 0
            outlineLayer.mask     = maskLayer

            layer.addSublayer(outlineLayer)

            let anim = CABasicAnimation(keyPath: "strokeEnd")
            anim.fromValue = 0; anim.toValue = 1
            anim.duration  = per
            anim.beginTime = CACurrentMediaTime() + Double(idx) * per
            anim.fillMode  = .forwards
            anim.isRemovedOnCompletion = false
            maskLayer.add(anim, forKey: "reveal")
        }
    }
}

struct UserStrokesMaskRevealAnimationView: UIViewRepresentable {
    let strokes:             [Stroke]
    let canvasSize:          CGFloat
    let sourceCanvasSize:    CGFloat
    let totalDuration:       Double
    let replayNonce:         Int
    let speedSensitivity:    Double
    let pressureSensitivity: Double
    let sizeFactor:          Double

    func makeUIView(context: Context) -> UserRevealContainerView {
        let v = UserRevealContainerView(); v.backgroundColor = .clear; return v
    }
    func updateUIView(_ v: UserRevealContainerView, context: Context) {
        v.renderAndAnimate(strokes: strokes, canvasSize: canvasSize,
                           sourceCanvasSize: sourceCanvasSize, totalDuration: totalDuration,
                           replayNonce: replayNonce,
                           speedSensitivity: speedSensitivity,
                           pressureSensitivity: pressureSensitivity,
                           sizeFactor: sizeFactor)
    }
}

// MARK: - Safe collection subscript

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - FlashcardPracticeView

struct FlashcardPracticeView: View {
    @EnvironmentObject var store: LearningSetsStore
    @EnvironmentObject var fsrsService: FSRSService
    @StateObject private var viewModel = DrawingViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: Setup state
    @State private var selectedSetIds: Set<UUID> = []
    @State private var schedulingMode: FlashcardSchedulingMode = .spacedRepetition
    @State private var inSession = false
    @State private var practiceMode: PracticeMode = .flip

    // MARK: Flip-mode state
    @State private var isFlipped = false
    @State private var showDifficultyPanel = false
    @State private var selectedDifficulty: DifficultyRating?

    // MARK: Draw-mode state
    @State private var activeCharacterBoxIndex = 0
    @State private var userStrokesPerBox: [[Stroke]] = []
    @State private var isDrawing = false
    @State private var drawModeDifficulty: DifficultyRating?

    // MARK: Session progress
    @State private var reviewedCardIds: Set<UUID> = []
    @State private var difficultyRatings: [UUID: DifficultyRating] = [:]
    @State private var showEndPage = false
    @State private var currentIndex = 0
    @State private var currentPrompt = ""
    @State private var currentCharacter = ""

    // MARK: Feedback state
    @State private var showFeedback = false
    @State private var savedUserStrokes: [[Stroke]] = []
    @State private var canvasSize: CGFloat = 400
    @State private var drawingAreaSize: CGSize = .zero
    @State private var replayNonce = 0

    // MARK: UI overlays
    @State private var showSettings = false
    @State private var showHelpGuide = false

    // MARK: Persisted settings
    @AppStorage("boundingBoxSize")         private var boundingBoxSize:          Double = 0.5
    @AppStorage("secondsPerStroke")        private var secondsPerStroke:         Double = 1.0
    @AppStorage("enableStrokeRemoval")     private var enableStrokeRemoval:      Bool   = false
    @AppStorage("strokeSpeedSensitivity")  private var strokeSpeedSensitivity:   Double = 1.5
    @AppStorage("strokePressureSensitivity") private var strokePressureSensitivity: Double = 1.5
    @AppStorage("strokeSizeFactor")        private var strokeSizeFactor:         Double = 1.0

    // MARK: Derived

    private var selectedSets: [LearningSet] {
        guard !selectedSetIds.isEmpty else {
            return store.activeSet.map { [$0] } ?? []
        }
        return store.sets.filter { selectedSetIds.contains($0.id) }
    }

    private var flashcardItems: [FlashcardItem] {
        let direction: ReviewDirection = practiceMode == .draw ? .promptToChar : .charToPrompt
        
        switch schedulingMode {
        case .spacedRepetition:
            return fsrsService.getCardsForSpacedRepetition(setIds: selectedSetIds, direction: direction)
        case .normalSequential:
            return fsrsService.getCardsSequential(setIds: selectedSetIds)
        case .normalShuffle:
            return fsrsService.getCardsShuffle(setIds: selectedSetIds)
        }
    }

    private var isCurrentSessionComplete: Bool { reviewedCardIds.count >= flashcardItems.count }

    private var setsWithDefinitions: [LearningSet] { store.sets.filter { $0.hasDefinitions } }
    private var allSetsSelected: Bool {
        !setsWithDefinitions.isEmpty && selectedSetIds.count == setsWithDefinitions.count
    }

    private var currentCharacters: [String] {
        Array(currentCharacter.unicodeScalars).map { String($0) }
    }

    // MARK: Body

    var body: some View {
        Group {
            if inSession {
                if showEndPage {
                    endPageView
                } else {
                    inSessionUI
                }
            } else {
                setupUI
            }
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $showHelpGuide) { NavigationStack { helpGuideView } }
    }

    // MARK: - Setup UI

    private var setupUI: some View {
        ZStack {
            Color("Secondary100").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    Text("Flashcard Practice")
                        .font(.system(size: horizontalSizeClass == .compact ? 28 : 40, weight: .bold))
                        .foregroundColor(Color("Primary900"))
                        .padding(.top, horizontalSizeClass == .compact ? 8 : 20)

                    setupCard
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Setup")
                .font(.title2).bold()
                .foregroundColor(Color("Primary900"))

            if setsWithDefinitions.isEmpty {
                emptyStateView
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    pickerSection
                    modeSelector
                    orderOptionsSection
                    startButton
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.7))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 24)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(Color("Neutral700"))
            Text("No sets with definitions")
                .font(.headline).foregroundColor(Color("Primary900"))
            Text("Add definitions to a learning set to practice flashcards")
                .font(.subheadline).foregroundColor(Color("Neutral700"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Learning Sets").font(.subheadline).foregroundColor(Color("Primary900"))
                Spacer()
                Button(allSetsSelected ? "Deselect All" : "Select All") {
                    selectedSetIds = allSetsSelected
                        ? []
                        : Set(setsWithDefinitions.map { $0.id })
                }
                .font(.caption).foregroundColor(Color("Primary700"))
            }

            ForEach(setsWithDefinitions) { set in
                setPickerRow(set)
            }

            if !selectedSetIds.isEmpty {
                Text("\(selectedSetIds.count) set(s) selected • \(flashcardItems.count) total cards")
                    .font(.caption).foregroundColor(Color("Neutral700"))
                    .padding(.top, 4)
            }
        }
    }

    private func setPickerRow(_ set: LearningSet) -> some View {
        let selected = selectedSetIds.contains(set.id)
        return Button {
            if selected { selectedSetIds.remove(set.id) } else { selectedSetIds.insert(set.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(selected ? Color("Primary700") : Color("Neutral400"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(set.name).font(.subheadline).foregroundColor(Color("Primary900"))
                    if let items = set.items {
                        Text("\(items.count) cards").font(.caption).foregroundColor(Color("Neutral700"))
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(selected ? Color("Primary700").opacity(0.1) : Color.white.opacity(0.9))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Practice Mode").font(.subheadline).foregroundColor(Color("Primary900"))
            Picker("Mode", selection: $practiceMode) {
                ForEach(PracticeMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var orderOptionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scheduling Mode").font(.subheadline).foregroundColor(Color("Primary900"))
            Picker("Scheduling", selection: $schedulingMode) {
                ForEach(FlashcardSchedulingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .padding(12)
            .background(Color.white.opacity(0.7))
            .cornerRadius(8)
        }
    }

    private var startButton: some View {
        Button(action: startSession) {
            Text("Start Practice")
                .font(.headline)
                .foregroundColor(Color("Secondary100"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color("Primary700"))
                .cornerRadius(10)
                .shadow(color: Color("Primary700").opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(selectedSetIds.isEmpty)
        .opacity(selectedSetIds.isEmpty ? 0.6 : 1.0)
    }

    // MARK: - In-Session UI

    private var inSessionUI: some View {
        VStack(spacing: 0) {
            sessionHeader
            progressBar
            drawingOrFeedbackArea
            bottomActionBar
        }
    }

    private var sessionHeader: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactHeader
            } else {
                regularHeader
            }
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                settingsHelpButtons(size: 34)
                Spacer()
            }
            Text(currentPrompt)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Color("Primary900"))
                .multilineTextAlignment(.center)
                .lineLimit(6).minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color("Secondary100").opacity(0.3))
    }

    private var regularHeader: some View {
        HStack(spacing: 16) {
            settingsHelpButtons(size: 44)
            Spacer()
            Text(currentPrompt)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Color("Primary900"))
                .multilineTextAlignment(.center)
                .lineLimit(3).minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
            Spacer()
            // Symmetry spacers
            Color.clear.frame(width: 44, height: 44)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
        .background(Color("Secondary100").opacity(0.3))
    }

    @ViewBuilder
    private func settingsHelpButtons(size: CGFloat) -> some View {
        iconButton("slider.horizontal.3", size: size,
                   color: Color("Primary700"),
                   background: showSettings ? Color("Primary700").opacity(0.2) : Color.white) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showSettings.toggle() }
        }
        iconButton("questionmark.circle", size: size, color: Color("Primary700")) {
            showHelpGuide = true
        }
    }

    private func iconButton(
        _ icon: String, size: CGFloat, color: Color,
        background: Color = Color.white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(size == 34 ? .callout : .title3)
                .foregroundColor(color)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }

    private var progressBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("\(reviewedCardIds.count) completed").font(.caption)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "doc.text").foregroundColor(Color("Primary700"))
                Text("\(flashcardItems.count) total").font(.caption)
            }
        }
        .foregroundColor(Color("Primary900"))
        .padding(.horizontal, 24).padding(.vertical, 6)
        .background(Color.white.opacity(0.7))
    }

    // MARK: Drawing / feedback canvas area

    @ViewBuilder
    private var drawingOrFeedbackArea: some View {
        if practiceMode == .flip {
            flipCardArea
        } else {
            if showFeedback {
                feedbackArea
            } else {
                drawingArea
                    .id(currentIndex) // force canvas recreation on card change
            }
        }
    }

    // MARK: Flip Card Mode

    private var flipCardArea: some View {
        GeometryReader { geo in
            ZStack {
                Color.white
                
                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    
                    // Flip card container
                    flipCardView
                        .frame(maxWidth: min(geo.size.width - 48, 500))
                        .frame(height: min(geo.size.height * 0.6, 400))
                    
                    Spacer(minLength: 20)
                    
                    // Difficulty rating panel (shown after flipping)
                    if isFlipped && !showDifficultyPanel {
                        Button(action: { withAnimation { showDifficultyPanel = true } }) {
                            Text("Rate Difficulty")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color("Primary700"))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    if showDifficultyPanel {
                        difficultyRatingPanel
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    Spacer(minLength: 20)
                }
            }
        }
    }

    private var flipCardView: some View {
        ZStack {
            // Back side (Character)
            cardSide(
                content: currentCharacter,
                backgroundColor: Color("Primary700"),
                textColor: .white,
                fontSize: 120,
                isVisible: isFlipped
            )
            .rotation3DEffect(
                .degrees(isFlipped ? 0 : 180),
                axis: (x: 0, y: 1, z: 0)
            )
            
            // Front side (Definition)
            cardSide(
                content: currentPrompt,
                backgroundColor: .white,
                textColor: Color("Primary900"),
                fontSize: 24,
                isVisible: !isFlipped
            )
            .rotation3DEffect(
                .degrees(isFlipped ? -180 : 0),
                axis: (x: 0, y: 1, z: 0)
            )
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isFlipped.toggle()
            }
        }
    }

    private func cardSide(content: String, backgroundColor: Color, textColor: Color, fontSize: CGFloat, isVisible: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .shadow(color: Color.black.opacity(0.15), radius: 15, x: 0, y: 8)
            
            VStack(spacing: 16) {
                if !isVisible {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundColor(textColor.opacity(0.5))
                    Text("Tap to flip")
                        .font(.caption)
                        .foregroundColor(textColor.opacity(0.5))
                }
                
                Text(content)
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.3)
                    .lineLimit(fontSize > 50 ? 2 : 10)
                    .padding(.horizontal, 32)
            }
        }
        .opacity(isVisible ? 1 : 0)
    }

    private var difficultyRatingPanel: some View {
        VStack(spacing: 16) {
            Text("How difficult was this card?")
                .font(.headline)
                .foregroundColor(Color("Primary900"))
            
            VStack(spacing: 12) {
                ForEach(DifficultyRating.allCases, id: \.self) { rating in
                    Button(action: {
                        selectedDifficulty = rating
                        rateAndProceed(rating)
                    }) {
                        HStack {
                            Image(systemName: rating.icon)
                                .font(.title3)
                            Text(rating.rawValue)
                                .font(.body)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(rating.color)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var drawingArea: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(currentCharacters.indices, id: \.self) { index in
                        characterInputBox(for: index, containerWidth: geo.size.width)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(Color.white)
        }
    }

    private func characterInputBox(for index: Int, containerWidth: CGFloat) -> some View {
        let boxSize = min(containerWidth - 48, 350)
        return VStack(spacing: 8) {
            Text("Character \(index + 1)")
                .font(.headline)
                .foregroundColor(Color("Primary900"))
            
            ZStack {
                Color.white
                
                // Crosshair guides
                crosshairLines(size: boxSize)
                
                if index < userStrokesPerBox.count {
                    ForEach(userStrokesPerBox[index], id: \.id) { stroke in
                        strokeView(stroke, color: Color.black)
                    }
                }
                
                if index == activeCharacterBoxIndex, let live = viewModel.currentStroke {
                    strokeView(live, color: Color.black.opacity(0.8))
                }
            }
            .frame(width: boxSize, height: boxSize)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(index == activeCharacterBoxIndex ? Color("Primary700") : Color.gray.opacity(0.3), lineWidth: index == activeCharacterBoxIndex ? 3 : 1)
            )
            .contentShape(Rectangle())
            .overlay(
                GeometryReader { geo in
                    TouchCaptureView(
                        onBegan: { pt, p in
                            activeCharacterBoxIndex = index
                            ensureBoxExists(at: index)
                            isDrawing = true
                            viewModel.beginStrokeWithPressure(at: pt, pressure: p)
                        },
                        onMoved: { pt, p in
                            if activeCharacterBoxIndex == index {
                                if viewModel.currentStroke == nil {
                                    viewModel.beginStrokeWithPressure(at: pt, pressure: p)
                                } else {
                                    viewModel.continueStrokeWithPressure(at: pt, pressure: p)
                                }
                            }
                        },
                        onEnded: {
                            if activeCharacterBoxIndex == index {
                                isDrawing = false
                                if let completedStroke = viewModel.currentStroke {
                                    userStrokesPerBox[index].append(completedStroke)
                                }
                                viewModel.endStroke()
                            }
                        },
                        drawingBounds: CGRect(origin: .zero, size: geo.size)
                    )
                }
            )
            
            Button(action: { clearBox(at: index) }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear")
                }
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    private func ensureBoxExists(at index: Int) {
        while userStrokesPerBox.count <= index {
            userStrokesPerBox.append([])
        }
    }

    private func clearBox(at index: Int) {
        guard index < userStrokesPerBox.count else { return }
        userStrokesPerBox[index].removeAll()
    }

    private var guideBoxOverlay: some View {
        GeometryReader { geo in
            let sq   = min(geo.size.width, geo.size.height)
            let box  = sq * CGFloat(boundingBoxSize)
            let ox   = (geo.size.width  - box) / 2
            let oy   = (geo.size.height - box) / 2
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color("Primary700").opacity(0.5), lineWidth: 2)
                crosshairLines(size: box)
            }
            .frame(width: box, height: box)
            .position(x: ox + box/2, y: oy + box/2)
        }
        .allowsHitTesting(false)
    }

    private func crosshairLines(size: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: size/2)); p.addLine(to: CGPoint(x: size, y: size/2))
            p.move(to: CGPoint(x: size/2, y: 0)); p.addLine(to: CGPoint(x: size/2, y: size))
        }
        .stroke(Color("Primary700").opacity(0.2),
                style: .init(lineWidth: 1, dash: [5, 5]))
    }

    private var crosshairOverlay: some View {
        GeometryReader { geo in
            crosshairLines(size: min(geo.size.width, geo.size.height))
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var feedbackArea: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    ForEach(currentCharacters.indices, id: \.self) { charIndex in
                        characterFeedbackRow(for: charIndex, containerWidth: geo.size.width)
                    }
                }
                .padding(24)
            }
            .background(Color.white)
        }
    }

    private var drawModeDifficultyPanel: some View {
        VStack(spacing: 16) {
            Text("How difficult was this card?")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(Color("Primary900"))
            
            HStack(spacing: 12) {
                ForEach(DifficultyRating.allCases, id: \.self) { rating in
                    Button(action: {
                        drawModeDifficulty = rating
                        let currentCard = flashcardItems[currentIndex]
                        difficultyRatings[currentCard.id] = rating
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: rating.icon)
                                .font(.title2)
                            Text(rating.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(rating.color)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private func characterFeedbackRow(for charIndex: Int, containerWidth: CGFloat) -> some View {
        let boxSize = min((containerWidth - 72) / 2, 300)
        
        return VStack(spacing: 12) {
            Text("Character \(charIndex + 1): \(currentCharacters[charIndex])")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Color("Primary900"))
            
            HStack(spacing: 16) {
                // User's strokes with animation
                VStack(spacing: 8) {
                    Text("Your Drawing")
                        .font(.headline)
                        .foregroundColor(Color("Primary700"))
                    
                    ZStack {
                        Color.white
                        
                        if charIndex < savedUserStrokes.count {
                            userStrokesAnimationView(for: charIndex, size: boxSize)
                        }
                    }
                    .frame(width: boxSize, height: boxSize)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Reference character with animation
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Text("Reference")
                            .font(.headline)
                            .foregroundColor(Color("Primary700"))
                        Spacer()
                    }
                    
                    ZStack {
                        // Animated reference
                        referenceAnimationView(for: charIndex, size: boxSize)
                            .frame(width: boxSize, height: boxSize)
                            .cornerRadius(12)
                        
                        // Static reference in top right corner (overlaid on top)
                        VStack {
                            HStack {
                                Spacer()
                                ZStack {
                                    Color.white.opacity(0.95)
                                    trueCharacterCanvas(for: charIndex, size: boxSize * 0.3)
                                }
                                .frame(width: boxSize * 0.3, height: boxSize * 0.3)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .padding(8)
                            }
                            Spacer()
                        }
                    }
                    .frame(width: boxSize, height: boxSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(Color("Secondary100").opacity(0.3))
        .cornerRadius(16)
    }

    private var replayButton: some View {
        Button(action: { replayNonce += 1 }) {
            Image(systemName: "arrow.clockwise")
                .font(.title3)
                .foregroundColor(Color("Primary700"))
                .padding(8)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }

    private func strokeView(_ stroke: Stroke, color: Color) -> some View {
        VariableWidthStrokeView(
            stroke: stroke, color: color,
            speedSensitivity: strokeSpeedSensitivity,
            pressureSensitivity: strokePressureSensitivity,
            sizeFactor: strokeSizeFactor
        )
    }

    // MARK: Reference character views

    private func trueCharacterCanvas(for charIndex: Int, size: CGFloat) -> some View {
        Group {
            if charIndex < currentCharacters.count {
                let character = currentCharacters[charIndex]
                let strokes = SVGParser.parseCharacter(character)
                ForEach(strokes.indices, id: \.self) { i in
                    ReferenceStrokeShapeView(
                        referenceStroke: strokes[i],
                        canvasSize: size)
                    .fill(Color.black.opacity(0.7))
                }
            }
        }
    }

    private func userStrokesAnimationView(for charIndex: Int, size: CGFloat) -> some View {
        Group {
            if charIndex < savedUserStrokes.count {
                let strokes = savedUserStrokes[charIndex]
                UserStrokesMaskRevealAnimationView(
                    strokes:             strokes,
                    canvasSize:          size,
                    sourceCanvasSize:    size,
                    totalDuration:       max(0.1, Double(strokes.count) * secondsPerStroke),
                    replayNonce:         replayNonce,
                    speedSensitivity:    strokeSpeedSensitivity,
                    pressureSensitivity: strokePressureSensitivity,
                    sizeFactor:          strokeSizeFactor
                )
                .id(replayNonce)
            }
        }
    }

    private func referenceAnimationView(for charIndex: Int, size: CGFloat) -> some View {
        Group {
            if charIndex < currentCharacters.count {
                let character = currentCharacters[charIndex]
                let refStrokes = SVGParser.parseCharacter(character)
                ReferenceStrokeMaskAnimationView(
                    referenceStrokes:    refStrokes,
                    userStrokes:         [],
                    strokeResults:       [],
                    originalCanvasSize:  size,
                    boundingBox:         nil,
                    canvasSize:          size,
                    totalDuration:       max(0.1, Double(refStrokes.count) * secondsPerStroke),
                    replayNonce:         replayNonce,
                    pause:               showSettings,
                    speedSensitivity:    strokeSpeedSensitivity,
                    pressureSensitivity: strokePressureSensitivity,
                    sizeFactor:          strokeSizeFactor
                )
                .id(replayNonce)
            }
        }
    }


    // MARK: Bottom action bar

    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            // Difficulty rating (shown after check in draw mode)
            if practiceMode == .draw && showFeedback && drawModeDifficulty == nil {
                compactDifficultyPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Action buttons
            HStack(spacing: 12) {
                if practiceMode == .draw {
                    checkButton
                    if showFeedback {
                        nextButton
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .background(Color("Secondary100").opacity(0.3))
        }
    }
    
    private var compactDifficultyPanel: some View {
        VStack(spacing: 12) {
            Text("Rate difficulty:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(Color("Primary900"))
            
            HStack(spacing: 8) {
                ForEach(DifficultyRating.allCases, id: \.self) { rating in
                    Button(action: {
                        withAnimation {
                            drawModeDifficulty = rating
                            let currentCard = flashcardItems[currentIndex]
                            difficultyRatings[currentCard.id] = rating
                            
                            // Update FSRS data for this card
                            fsrsService.reviewPromptToChar(cardId: currentCard.id, rating: rating)
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: rating.icon)
                                .font(.title3)
                            Text(rating.rawValue)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(rating.color)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
    }


    private var checkButton: some View {
        Button(action: finishCharacter) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Check")
            }
            .font(.headline).foregroundColor(Color("Secondary100"))
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color("Primary700")).cornerRadius(12)
            .shadow(color: Color("Primary700").opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(showFeedback)
        .opacity(showFeedback ? 0.5 : 1.0)
    }

    private var nextButton: some View {
        Button(action: nextCard) {
            HStack {
                Text("Next")
                Image(systemName: "arrow.right")
            }
            .font(.headline).foregroundColor(Color("Primary700"))
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color.white).cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color("Primary700"), lineWidth: 2))
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .disabled(showFeedback && drawModeDifficulty == nil)
        .opacity((showFeedback && drawModeDifficulty == nil) ? 0.5 : 1.0)
    }


    // MARK: End page

    private var endPageView: some View {
        VStack(spacing: 20) {
            Text("Session Complete")
                .font(.largeTitle).bold().foregroundColor(Color("Primary900"))
            Text("\(reviewedCardIds.count) cards reviewed")
                .font(.title2).foregroundColor(Color("Primary700"))
            Button("Start Again") { startSession() }
                .font(.headline).foregroundColor(.white)
                .padding(.horizontal, 32).padding(.vertical, 14)
                .background(Color("Primary700")).cornerRadius(12)
            Button("Back to Setup") { inSession = false }
                .font(.subheadline).foregroundColor(Color("Primary700"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("Secondary100"))
    }

    // MARK: Settings

    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                settingsPanel.padding(.top, 12)
                NavigationLink(destination: helpGuideView) {
                    HStack {
                        Image(systemName: "questionmark.circle").foregroundColor(Color("Primary700"))
                        Text("How to Use").font(.subheadline).foregroundColor(Color("Primary900"))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                            .foregroundColor(Color("Neutral700"))
                    }
                    .padding(16).background(Color.white.opacity(0.95)).cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(.horizontal, 24).padding(.top, 16)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button("Reset") { resetParameters() }
                    .font(.caption).foregroundColor(.white)
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .background(Color("Primary700")).cornerRadius(8)
            }

            settingSlider("Bounding Box Size",
                          value: $boundingBoxSize, range: 0.2...1.0, step: 0.05,
                          format: { String(format: "%.0f%%", $0 * 100) })

            settingSlider("Animation Speed",
                          value: $secondsPerStroke, range: 0.10...1.50, step: 0.05,
                          format: { String(format: "%.1fs / stroke", $0) })

            settingSlider("Stroke Size",
                          value: $strokeSizeFactor, range: 0.5...2.0, step: 0.05,
                          format: { String(format: "%.2fx", $0) })

            settingSlider("Pressure Sensitivity",
                          value: $strokePressureSensitivity, range: 0.25...2.0, step: 0.05,
                          format: { String(format: "%.2fx", $0) })

            settingSlider("Speed Sensitivity",
                          value: $strokeSpeedSensitivity, range: 0.25...3.0, step: 0.05,
                          format: { String(format: "%.2fx", $0) })

            HStack {
                Text("Remove Bad Strokes").font(.subheadline)
                Spacer()
                Toggle("", isOn: $enableStrokeRemoval).labelsHidden()
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 24).padding(.top, 8)
    }

    private func settingSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(Color("Primary700"))
            }
            Slider(value: value, in: range, step: step).accentColor(Color("Primary700"))
        }
    }

    // MARK: Help guide

    private var helpGuideView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                helpSection("Overview", icon: "info.circle.fill") {
                    Text("The purpose of Chinese Character Autograder is to help you learn new Chinese Characters and write them well. The app reinforces strokes you draw correctly, and rejects or adjusts strokes that need work.")
                        .font(.body).foregroundColor(Color("Primary900"))
                }

                Divider()

                helpSection("How to Use Flashcards", icon: "hand.draw.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        helpStep("1", "Select a learning set that has definitions")
                        helpStep("2", "Read the prompt and draw the character")
                        helpStep("3", "Tap 'Check' to see your feedback")
                        helpStep("4", "Study feedback, then retry or advance")
                        helpStep("5", "Use Settings to adjust stroke appearance and bounding box")
                    }
                }

                Divider()

                helpSection("Understanding Feedback", icon: "paintpalette.fill") {
                    Text("Review your strokes alongside the animated reference character to improve your writing.")
                        .font(.subheadline).foregroundColor(Color("Primary900"))
                }

                Divider()

                helpSection("Other Notes", icon: "lightbulb.fill") {
                    Text("Strokes are matched based on position relative to the bounding box. Draw to the scale of the box for accurate results.")
                        .font(.subheadline).foregroundColor(Color("Primary900"))
                }

                Spacer(minLength: 40)
            }
            .padding(20)
        }
        .background(Color("Secondary100").opacity(0.3))
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.large)
    }

    private func helpSection<Content: View>(
        _ title: String, icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.title2.bold()).foregroundColor(Color("Primary900"))
            content()
        }
    }

    private func helpStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold()).foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Color("Primary700")).clipShape(Circle())
            Text(text).font(.subheadline).foregroundColor(Color("Primary900"))
        }
    }

    // MARK: - Session logic

    private func startSession() {
        print("🎯 Start Practice clicked - flashcardItems count: \(flashcardItems.count)")
        print("🎯 Selected sets: \(selectedSetIds)")
        print("🎯 Scheduling mode: \(schedulingMode)")
        guard !flashcardItems.isEmpty else {
            print("❌ Cannot start - flashcardItems is empty!")
            return
        }
        inSession              = true
        showEndPage            = false
        reviewedCardIds        = []
        difficultyRatings      = [:]
        isFlipped              = false
        showDifficultyPanel    = false
        selectedDifficulty     = nil
        resetDrawState()
        prepareInitialPrompt()
    }

    private func resetDrawState() {
        showFeedback              = false
        savedUserStrokes          = []
        userStrokesPerBox         = []
        activeCharacterBoxIndex   = 0
        drawModeDifficulty        = nil
        viewModel.clear()
        isDrawing = false
    }

    private func prepareInitialPrompt() {
        let unreviewed = flashcardItems.filter { !reviewedCardIds.contains($0.id) }
        currentIndex = unreviewed.first.flatMap { flashcardItems.firstIndex(of: $0) } ?? 0
        if !flashcardItems.isEmpty {
            currentPrompt     = flashcardItems[currentIndex].definition
            currentCharacter  = flashcardItems[currentIndex].hanzi
        }
    }

    private func nextCard() {
        guard !flashcardItems.isEmpty else { return }
        resetDrawState()
        resetFlipState()
        if schedulingMode == .normalShuffle {
            currentIndex = Int.random(in: 0..<flashcardItems.count)
        } else {
            currentIndex = (currentIndex + 1) % flashcardItems.count
        }
        currentPrompt    = flashcardItems[currentIndex].definition
        currentCharacter = flashcardItems[currentIndex].hanzi
    }

    private func resetFlipState() {
        isFlipped = false
        showDifficultyPanel = false
        selectedDifficulty = nil
    }

    private func rateAndProceed(_ rating: DifficultyRating) {
        let currentCard = flashcardItems[currentIndex]
        reviewedCardIds.insert(currentCard.id)
        difficultyRatings[currentCard.id] = rating
        
        // Update FSRS data based on practice mode
        if practiceMode == .flip {
            fsrsService.reviewCharToPrompt(cardId: currentCard.id, rating: rating)
        }
        // Note: Draw mode calls reviewPromptToChar in the difficulty panel button action
        
        if reviewedCardIds.count >= flashcardItems.count {
            showEndPage = true
        } else {
            nextCard()
        }
    }

    private func previousCard() {
        guard !flashcardItems.isEmpty, schedulingMode == .normalSequential, currentIndex > 0 else { return }
        resetDrawState()
        resetFlipState()
        currentIndex    -= 1
        currentPrompt    = flashcardItems[currentIndex].definition
        currentCharacter = flashcardItems[currentIndex].hanzi
    }

    private func finishCharacter() {
        guard !currentCharacter.isEmpty else { return }
        
        // Save all strokes from each box
        savedUserStrokes = userStrokesPerBox
        
        // Show feedback
        showFeedback = true
        
        // Mark as reviewed
        let currentCard = flashcardItems[currentIndex]
        reviewedCardIds.insert(currentCard.id)
    }

    private func restartSet() {
        resetDrawState()
        if schedulingMode == .normalShuffle { currentIndex = Int.random(in: 0..<flashcardItems.count) } else { currentIndex = 0 }
        currentPrompt    = flashcardItems[currentIndex].definition
        currentCharacter = flashcardItems[currentIndex].hanzi
    }

    private func resetParameters() {
        boundingBoxSize          = 0.8
        secondsPerStroke         = 0.5
        enableStrokeRemoval      = false
        strokeSpeedSensitivity   = 1.0
        strokePressureSensitivity = 1.0
        strokeSizeFactor         = 1.0
    }
}
