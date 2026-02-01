#if canImport(UIKit)
import UIKit

@MainActor
final class EditorRuledBackgroundView: UIView {
    weak var textView: UITextView?

    var isEnabled: Bool = false {
        didSet {
            isHidden = !isEnabled
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isEnabled {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard isEnabled else { return }
        guard let tv = textView else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let font = tv.font ?? UIFont.preferredFont(forTextStyle: .body)
        let lineHeight = max(12, font.lineHeight.rounded(.toNearestOrAwayFromZero))

        // Draw lines aligned to the text container inset.
        let startY = tv.textContainerInset.top

        // Use a subtle tint derived from the editor text color.
        let base = (tv.textColor ?? UIColor.label)
        let stroke = base.withAlphaComponent(0.08)

        let scale = max(1.0, tv.traitCollection.displayScale)
        let onePx = 1.0 / scale

        ctx.saveGState()
        ctx.setStrokeColor(stroke.cgColor)
        ctx.setLineWidth(onePx)

        // Only draw the lines that intersect the current invalidated rect.
        let minY = rect.minY
        let maxY = rect.maxY

        let firstIndex = max(0, Int(floor((minY - startY) / lineHeight)))
        var y = startY + CGFloat(firstIndex) * lineHeight

        let x1: CGFloat = 0
        let x2: CGFloat = bounds.width

        while y <= maxY + lineHeight {
            if y >= minY - lineHeight {
                ctx.move(to: CGPoint(x: x1, y: y))
                ctx.addLine(to: CGPoint(x: x2, y: y))
            }
            y += lineHeight
        }

        ctx.strokePath()
        ctx.restoreGState()
    }
}

#endif
