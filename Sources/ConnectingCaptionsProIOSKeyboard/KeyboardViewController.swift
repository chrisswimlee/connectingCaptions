import UIKit

/// Inserts the last committed Pro caption. The globe key returns to the system keyboard.
/// This extension cannot use the microphone.
/// Info.plist asks for this exact class. A module prefix looks up a name this binary does not register.
@objc(KeyboardViewController)
final class KeyboardViewController: UIInputViewController {
    private let captionLabel = UILabel()
    private let insertButton = UIButton(type: .system)
    private let keyboardButton = UIButton(type: .system)
    private let insertObserver = DarwinInsertObserver()

    private static let suite = "group.com.connectingcaptions.ios.pro"
    private static let lineKey = "keyboard.insertLine"
    private static let allowedKey = "keyboard.insertAllowed"
    private static let didChange = "com.connectingcaptions.ios.pro.keyboard.insertLine"

    override var needsInputModeSwitchKey: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .secondarySystemBackground

        self.captionLabel.font = .preferredFont(forTextStyle: .title3)
        self.captionLabel.adjustsFontForContentSizeCategory = true
        self.captionLabel.numberOfLines = 0
        self.captionLabel.textAlignment = .natural

        var insertConfig = UIButton.Configuration.filled()
        insertConfig.title = "Insert caption"
        insertConfig.image = UIImage(systemName: "text.insert")
        insertConfig.imagePadding = 8
        self.insertButton.configuration = insertConfig
        self.insertButton.accessibilityLabel = "Insert caption"
        self.insertButton.addTarget(self, action: #selector(self.insertCaption), for: .touchUpInside)

        var keyboardConfig = UIButton.Configuration.gray()
        keyboardConfig.title = "Keyboards"
        keyboardConfig.image = UIImage(systemName: "globe")
        keyboardConfig.imagePadding = 8
        self.keyboardButton.configuration = keyboardConfig
        self.keyboardButton.accessibilityLabel = "Next keyboard"
        self.keyboardButton.addTarget(self, action: #selector(self.nextKeyboard), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [self.insertButton, self.keyboardButton])
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [self.captionLabel, buttons])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -8),
        ])
        self.insertObserver.start(name: Self.didChange) { [weak self] in
            self?.reload()
        }
        self.reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.reload()
    }

    deinit {
        self.insertObserver.stop(name: Self.didChange)
    }

    private func reload() {
        let defaults = UserDefaults(suiteName: Self.suite)
        let line = defaults?.string(forKey: Self.lineKey) ?? ""
        let allowed = defaults?.object(forKey: Self.allowedKey) as? Bool
        if !self.hasFullAccess {
            self.captionLabel.text = "Allow Full Access so this keyboard can read the last caption."
            self.insertButton.isEnabled = false
        } else if allowed == true, !line.isEmpty {
            if line != self.captionLabel.text {
                UIAccessibility.post(notification: .announcement, argument: line)
            }
            self.captionLabel.text = line
            self.insertButton.isEnabled = true
        } else {
            self.captionLabel.text = "Listen in Connecting Captions Pro, then insert the last line."
            self.insertButton.isEnabled = false
        }
    }

    @objc private func insertCaption() {
        let defaults = UserDefaults(suiteName: Self.suite)
        let line = defaults?.string(forKey: Self.lineKey) ?? ""
        let allowed = defaults?.object(forKey: Self.allowedKey) as? Bool ?? false
        guard allowed, !line.isEmpty else { return }
        self.textDocumentProxy.insertText(line)
    }

    @objc private func nextKeyboard() {
        self.advanceToNextInputMode()
    }
}

/// Darwin notifications have no owner. The box outlives a caption that arrives
/// as the keyboard is closing, and the reload runs only while the keyboard is here.
final class DarwinInsertObserver {
    private var pointer: UnsafeMutableRawPointer?
    private var reload: (() -> Void)?

    func start(name: String, reload: @escaping () -> Void) {
        self.stop(name: name)
        self.reload = reload
        let pointer = Unmanaged.passRetained(self).toOpaque()
        self.pointer = pointer
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            pointer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<DarwinInsertObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    box.reload?()
                }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    func stop(name: String) {
        guard let pointer = self.pointer else { return }
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            pointer,
            CFNotificationName(name as CFString),
            nil
        )
        self.pointer = nil
        self.reload = nil
        Unmanaged<DarwinInsertObserver>.fromOpaque(pointer).release()
    }
}
