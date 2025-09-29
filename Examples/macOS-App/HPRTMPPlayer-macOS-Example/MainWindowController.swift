import AppKit
import HPRTMPPlayer

class MainWindowController: NSWindowController {

    private var rtmpPlayerView: RTMPPlayerView!
    private var statusLabel: NSTextField!
    private var urlTextField: NSTextField!
    private var playButton: NSButton!
    private var stopButton: NSButton!
    private var pauseButton: NSButton!
    private var resumeButton: NSButton!
    private var restartButton: NSButton!
    private var performanceButton: NSButton!
    private var performanceLabel: NSTextField!
    private var performanceTimer: Timer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HPRTMPPlayer macOS示例"
        window.center()
        window.minSize = NSSize(width: 600, height: 500)

        self.init(window: window)
        setupContent()
    }

    private func setupContent() {
        guard let window = window else { return }

        let contentView = NSView()
        contentView.wantsLayer = true
        window.contentView = contentView

        setupRTMPPlayer()
        setupUI()
        setupConstraints(in: contentView)
    }

    private func setupRTMPPlayer() {
        rtmpPlayerView = RTMPPlayerView()
        rtmpPlayerView.wantsLayer = true
        rtmpPlayerView.layer?.backgroundColor = NSColor.black.cgColor
        rtmpPlayerView.layer?.cornerRadius = 8

        rtmpPlayerView.playbackStateDidChange = { [weak self] state in
            self?.handlePlaybackStateChange(state)
        }
    }

    private func setupUI() {
        // URL输入框
        urlTextField = NSTextField()
        urlTextField.placeholderString = "输入RTMP URL"
        urlTextField.stringValue = "rtmp://192.168.11.23:1936/live/test"

        // 状态标签
        statusLabel = createLabel(text: "状态: 空闲", fontSize: 16, weight: .medium)

        // 性能监控标签
        performanceLabel = createLabel(text: "", fontSize: 12, weight: .regular)
        performanceLabel.maximumNumberOfLines = 4

        // 按钮
        playButton = createButton(title: "播放", action: #selector(playButtonClicked))
        stopButton = createButton(title: "停止", action: #selector(stopButtonClicked))
        pauseButton = createButton(title: "暂停", action: #selector(pauseButtonClicked))
        resumeButton = createButton(title: "恢复", action: #selector(resumeButtonClicked))
        restartButton = createButton(title: "重启", action: #selector(restartButtonClicked))
        performanceButton = createButton(title: "启用性能监控", action: #selector(performanceButtonClicked))

        // 初始状态设置
        stopButton.isEnabled = false
        pauseButton.isEnabled = false
        resumeButton.isEnabled = false
        restartButton.isEnabled = false
    }

    private func createLabel(text: String, fontSize: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField()
        label.stringValue = text
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.alignment = .center
        label.font = .systemFont(ofSize: fontSize, weight: weight)
        return label
    }

    private func createButton(title: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.title = title
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        button.layer?.cornerRadius = 8
        return button
    }

    private func setupConstraints(in contentView: NSView) {
        let controlsStackView = NSStackView(views: [
            urlTextField,
            createButtonRow1(),
            createButtonRow2(),
            performanceButton,
            statusLabel,
            performanceLabel
        ])
        controlsStackView.orientation = .vertical
        controlsStackView.spacing = 12
        controlsStackView.alignment = .centerX

        [rtmpPlayerView, controlsStackView].forEach {
            $0?.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0!)
        }

        NSLayoutConstraint.activate([
            // RTMP播放器视图
            rtmpPlayerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            rtmpPlayerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rtmpPlayerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rtmpPlayerView.heightAnchor.constraint(equalTo: rtmpPlayerView.widthAnchor, multiplier: 9.0/16.0),

            // 控制面板
            controlsStackView.topAnchor.constraint(equalTo: rtmpPlayerView.bottomAnchor, constant: 20),
            controlsStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            controlsStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            controlsStackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),

            // URL输入框
            urlTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
            urlTextField.heightAnchor.constraint(equalToConstant: 30),

            // 按钮高度
            playButton.heightAnchor.constraint(equalToConstant: 32),
            stopButton.heightAnchor.constraint(equalToConstant: 32),
            pauseButton.heightAnchor.constraint(equalToConstant: 32),
            resumeButton.heightAnchor.constraint(equalToConstant: 32),
            restartButton.heightAnchor.constraint(equalToConstant: 32),
            performanceButton.heightAnchor.constraint(equalToConstant: 32),

            // 按钮宽度
            playButton.widthAnchor.constraint(equalToConstant: 100),
            stopButton.widthAnchor.constraint(equalToConstant: 100),
            pauseButton.widthAnchor.constraint(equalToConstant: 100),
            resumeButton.widthAnchor.constraint(equalToConstant: 100),
            restartButton.widthAnchor.constraint(equalToConstant: 100),
            performanceButton.widthAnchor.constraint(equalToConstant: 150)
        ])
    }

    private func createButtonRow1() -> NSStackView {
        let stackView = NSStackView(views: [playButton, stopButton, pauseButton])
        stackView.orientation = .horizontal
        stackView.spacing = 12
        stackView.distribution = .fillEqually
        return stackView
    }

    private func createButtonRow2() -> NSStackView {
        let stackView = NSStackView(views: [resumeButton, restartButton])
        stackView.orientation = .horizontal
        stackView.spacing = 12
        stackView.distribution = .fillEqually
        return stackView
    }

    @objc private func playButtonClicked() {
        let urlString = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else {
            showAlert(message: "请输入有效的RTMP URL")
            return
        }

        rtmpPlayerView.play(urlString)
    }

    @objc private func stopButtonClicked() {
        rtmpPlayerView.stop()
    }

    @objc private func pauseButtonClicked() {
        rtmpPlayerView.pause()
    }

    @objc private func resumeButtonClicked() {
        rtmpPlayerView.resume()
    }

    @objc private func restartButtonClicked() {
        let urlString = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else {
            showAlert(message: "请输入有效的RTMP URL")
            return
        }

        rtmpPlayerView.restart()
    }

    @objc private func performanceButtonClicked() {
        rtmpPlayerView.enablePerformanceMonitoring()
        performanceButton.title = "性能监控已启用"
        performanceButton.isEnabled = false

        // 开始定期更新性能统计
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePerformanceStats()
        }
    }

    private func updatePerformanceStats() {
        let stats = rtmpPlayerView.getPerformanceStats()

        DispatchQueue.main.async {
            self.performanceLabel.stringValue = """
            FPS: \(String(format: "%.1f", stats.fps)) | 总帧数: \(stats.totalFrames)
            丢帧: \(stats.droppedFrames) | 平均帧时间: \(String(format: "%.2f", stats.averageFrameTime * 1000))ms
            """
        }
    }

    private func handlePlaybackStateChange(_ state: RTMPPlayer.PlaybackState) {
        DispatchQueue.main.async {
            switch state {
            case .idle:
                self.statusLabel.stringValue = "状态: 空闲"
                self.updateButtonStates(canPlay: true, canStop: false, canPause: false, canResume: false, canRestart: false)

            case .connecting:
                self.statusLabel.stringValue = "状态: 连接中..."
                self.updateButtonStates(canPlay: false, canStop: true, canPause: false, canResume: false, canRestart: false)

            case .playing:
                self.statusLabel.stringValue = "状态: 播放中"
                self.updateButtonStates(canPlay: false, canStop: true, canPause: true, canResume: false, canRestart: true)

            case .paused:
                self.statusLabel.stringValue = "状态: 已暂停"
                self.updateButtonStates(canPlay: false, canStop: true, canPause: false, canResume: true, canRestart: true)

            case .stopped:
                self.statusLabel.stringValue = "状态: 已停止"
                self.updateButtonStates(canPlay: true, canStop: false, canPause: false, canResume: false, canRestart: false)

            case .error(let error):
                self.statusLabel.stringValue = "状态: 错误 - \(error.localizedDescription)"
                self.updateButtonStates(canPlay: true, canStop: false, canPause: false, canResume: false, canRestart: true)
                self.showAlert(message: "播放错误: \(error.localizedDescription)")
            }
        }
    }

    private func updateButtonStates(canPlay: Bool, canStop: Bool, canPause: Bool, canResume: Bool, canRestart: Bool) {
        playButton.isEnabled = canPlay
        stopButton.isEnabled = canStop
        pauseButton.isEnabled = canPause
        resumeButton.isEnabled = canResume
        restartButton.isEnabled = canRestart
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "提示"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    deinit {
        performanceTimer?.invalidate()
    }
}