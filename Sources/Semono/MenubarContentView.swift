import AppKit

final class MenubarContentView: NSView {
    let valueLabel = NSTextField(labelWithString: "")
    let typeLabel  = NSTextField(labelWithString: "")

    var displayText: String = "" { didSet { valueLabel.stringValue = displayText } }
    var displayType: String = "CPU" { didSet { typeLabel.stringValue = displayType } }

    override init(frame: NSRect) {
        super.init(frame: frame)

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.alignment = .center
        valueLabel.textColor = .labelColor

        typeLabel.font = NSFont.systemFont(ofSize: 7, weight: .regular)
        typeLabel.alignment = .center
        typeLabel.textColor = .secondaryLabelColor

        addSubview(valueLabel)
        addSubview(typeLabel)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.62),

            typeLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: -1),
            typeLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            typeLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            typeLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        translatesAutoresizingMaskIntoConstraints = false
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 32, height: NSStatusBar.system.thickness)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if let menu = self.menu {
            menu.popUp(positioning: nil, at: .zero, in: self)
        }
    }
}
