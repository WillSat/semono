import AppKit

final class MenubarContentView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private let typeLabel  = NSTextField(labelWithString: "")

    var displayText: String = "" { didSet { valueLabel.stringValue = displayText } }
    var displayType: String = "CPU" { didSet { typeLabel.stringValue = displayType } }

    /// Width required by the currently displayed content.
    var fittingWidth: CGFloat {
        let valueW = valueLabel.attributedStringValue.size().width
        let typeW = typeLabel.attributedStringValue.size().width
        return ceil(max(valueW, typeW)) + 10
    }

    override init(frame: NSRect) {
        super.init(frame: frame)

        valueLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byClipping

        typeLabel.font = .systemFont(ofSize: 6.5, weight: .medium)
        typeLabel.alignment = .center
        typeLabel.textColor = .secondaryLabelColor
        typeLabel.lineBreakMode = .byClipping

        addSubview(valueLabel)
        addSubview(typeLabel)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            typeLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: -1),
            typeLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            typeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            typeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])

        translatesAutoresizingMaskIntoConstraints = false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fittingWidth, height: NSStatusBar.system.thickness)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if let menu = self.menu {
            menu.popUp(positioning: nil, at: .zero, in: self)
        }
    }
}
