#if canImport(UIKit)
import UIKit

@MainActor
final class EditorSectionGutterView: UIView {
    weak var textView: UITextView?

    var brackets: [SectionBracket] = [] {
        didSet {
            setNeedsDisplay()
        }
    }

    var onTapBracket: ((SectionBracket) -> Void)?

    private var labelHitTargets: [(rect: CGRect, bracket: SectionBracket)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let tv = textView else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        guard let layoutManager = tv.layoutManager as NSLayoutManager? else { return }

        labelHitTargets.removeAll(keepingCapacity: true)

        let gutterWidth = max(28, tv.textContainerInset.left - 12)
        let x: CGFloat = 10
        let lineWidth: CGFloat = 2

        let visibleContent = CGRect(origin: tv.contentOffset, size: tv.bounds.size)

        ctx.saveGState()
        ctx.setLineWidth(lineWidth)

        for b in brackets {
            guard let labelBars = b.labelBars else { continue }

            guard let top = lineBoundsInContentCoordinates(lineIndex: b.startLineIndex, textView: tv, layoutManager: layoutManager) else { continue }
            guard let bottom = lineBoundsInContentCoordinates(lineIndex: b.endLineIndex, textView: tv, layoutManager: layoutManager) else { continue }

            let topY = top.minY
            let bottomY = bottom.maxY

            if bottomY < visibleContent.minY - 40 || topY > visibleContent.maxY + 40 {
                continue
            }

            let strokeColor = (b.isLocked ? tv.tintColor : tv.textColor ?? .label).withAlphaComponent(b.isLocked ? 0.62 : 0.28)
            ctx.setStrokeColor(strokeColor.cgColor)

            // Convert to view coordinates.
            let y1 = topY - tv.contentOffset.y
            let y2 = bottomY - tv.contentOffset.y

            // Bracket: vertical line with small caps.
            let cap: CGFloat = min(12, gutterWidth - x - 4)
            ctx.move(to: CGPoint(x: x + cap, y: y1))
            ctx.addLine(to: CGPoint(x: x, y: y1))
            ctx.addLine(to: CGPoint(x: x, y: y2))
            ctx.addLine(to: CGPoint(x: x + cap, y: y2))
            ctx.strokePath()

            // Label bubble.
            let label = "\(labelBars)"
            let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: (tv.textColor ?? .label).withAlphaComponent(0.9),
            ]
            let textSize = (label as NSString).size(withAttributes: attrs)
            let bubblePaddingX: CGFloat = 8
            let bubblePaddingY: CGFloat = 5
            let bubbleW = textSize.width + bubblePaddingX * 2
            let bubbleH = textSize.height + bubblePaddingY * 2

            let midY = (y1 + y2) / 2
            let bubbleX = min(bounds.width - bubbleW - 4, x + cap + 8)
            let bubbleY = midY - bubbleH / 2

            let bubbleRect = CGRect(x: bubbleX, y: bubbleY, width: bubbleW, height: bubbleH)
            let bubblePath = UIBezierPath(roundedRect: bubbleRect, cornerRadius: bubbleH / 2)

            let fill = (tv.textColor ?? .label).withAlphaComponent(b.isLocked ? 0.14 : 0.08)
            fill.setFill()
            bubblePath.fill()

            (label as NSString).draw(at: CGPoint(x: bubbleRect.minX + bubblePaddingX, y: bubbleRect.minY + bubblePaddingY), withAttributes: attrs)

            labelHitTargets.append((rect: bubbleRect.insetBy(dx: -8, dy: -6), bracket: b))
        }

        ctx.restoreGState()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Only intercept taps on labels; otherwise let the text view handle scrolling/taps.
        for t in labelHitTargets {
            if t.rect.contains(point) {
                return self
            }
        }
        return nil
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        let p = gr.location(in: self)
        guard let match = labelHitTargets.first(where: { $0.rect.contains(p) }) else { return }
        onTapBracket?(match.bracket)
    }

    private func lineBoundsInContentCoordinates(
        lineIndex: Int,
        textView: UITextView,
        layoutManager: NSLayoutManager
    ) -> CGRect? {
        let ns = textView.text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        if fullRange.length == 0 {
            return nil
        }

        var ranges: [NSRange] = []
        ranges.reserveCapacity(64)
        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, r, _, _ in
            ranges.append(r)
        }

        if lineIndex < 0 || lineIndex >= ranges.count {
            return nil
        }

        let charRange = ranges[lineIndex]
        if charRange.length <= 0 {
            return nil
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
        rect.origin.x += textView.textContainerInset.left
        rect.origin.y += textView.textContainerInset.top
        return rect
    }
}

#endif
