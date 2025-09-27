// 基本使用示例
// 注意：这个示例需要在iOS项目中运行

#if canImport(UIKit)
import UIKit
import HPRTMPPlayer

class BasicUsageViewController: UIViewController {

    private var rtmpPlayer: RTMPPlayerViewController!

    override func viewDidLoad() {
        super.viewDidLoad()

        setupRTMPPlayer()
        setupUI()
    }

    private func setupRTMPPlayer() {
        // 创建RTMP播放器
        rtmpPlayer = RTMPPlayerViewController()

        // 设置状态变化回调
        rtmpPlayer.playbackStateDidChange = { [weak self] state in
            self?.handlePlaybackStateChange(state)
        }

        // 添加到视图层次
        addChild(rtmpPlayer)
        view.addSubview(rtmpPlayer.view)
        rtmpPlayer.didMove(toParent: self)

        // 设置约束
        rtmpPlayer.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rtmpPlayer.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            rtmpPlayer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            rtmpPlayer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            rtmpPlayer.view.heightAnchor.constraint(equalToConstant: 300)
        ])
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // 播放按钮
        let playButton = UIButton(type: .system)
        playButton.setTitle("播放", for: .normal)
        playButton.addTarget(self, action: #selector(playButtonTapped), for: .touchUpInside)

        // 停止按钮
        let stopButton = UIButton(type: .system)
        stopButton.setTitle("停止", for: .normal)
        stopButton.addTarget(self, action: #selector(stopButtonTapped), for: .touchUpInside)

        // 暂停按钮
        let pauseButton = UIButton(type: .system)
        pauseButton.setTitle("暂停", for: .normal)
        pauseButton.addTarget(self, action: #selector(pauseButtonTapped), for: .touchUpInside)

        // 恢复按钮
        let resumeButton = UIButton(type: .system)
        resumeButton.setTitle("恢复", for: .normal)
        resumeButton.addTarget(self, action: #selector(resumeButtonTapped), for: .touchUpInside)

        // 状态标签
        let statusLabel = UILabel()
        statusLabel.text = "状态: 空闲"
        statusLabel.textAlignment = .center
        statusLabel.tag = 100 // 用于后续更新

        // 堆栈视图
        let stackView = UIStackView(arrangedSubviews: [
            playButton, stopButton, pauseButton, resumeButton, statusLabel
        ])
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: rtmpPlayer.view.bottomAnchor, constant: 40),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    @objc private func playButtonTapped() {
        // 使用测试RTMP流URL
        let testURL = "rtmp://live.example.com/live/stream"
        rtmpPlayer.play(testURL)
    }

    @objc private func stopButtonTapped() {
        rtmpPlayer.stop()
    }

    @objc private func pauseButtonTapped() {
        rtmpPlayer.pause()
    }

    @objc private func resumeButtonTapped() {
        rtmpPlayer.resume()
    }

    private func handlePlaybackStateChange(_ state: RTMPPlayerViewController.PlaybackState) {
        DispatchQueue.main.async {
            let statusLabel = self.view.viewWithTag(100) as? UILabel

            switch state {
            case .idle:
                statusLabel?.text = "状态: 空闲"
            case .connecting:
                statusLabel?.text = "状态: 连接中..."
            case .playing:
                statusLabel?.text = "状态: 播放中"
            case .paused:
                statusLabel?.text = "状态: 已暂停"
            case .stopped:
                statusLabel?.text = "状态: 已停止"
            case .error(let error):
                statusLabel?.text = "状态: 错误 - \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 使用不同RTMP流的示例

extension BasicUsageViewController {

    // 播放不同类型的RTMP流
    func playDifferentStreams() {

        // 1. 标准RTMP流
        let standardRTMP = "rtmp://live.example.com/live/stream1"

        // 2. 带认证的RTMP流
        let authenticatedRTMP = "rtmp://username:password@live.example.com/live/stream2"

        // 3. 不同端口的RTMP流
        let customPortRTMP = "rtmp://live.example.com:1936/live/stream3"

        // 4. 安全RTMP流
        let secureRTMP = "rtmps://secure.example.com/live/stream4"

        // 示例：播放标准RTMP流
        rtmpPlayer.play(standardRTMP)
    }

    // 配置播放器选项
    func configurePlayerOptions() {
        // 启用自动重连
        rtmpPlayer.enableAutoReconnect = true

        // 设置详细的状态回调
        rtmpPlayer.playbackStateDidChange = { state in
            print("播放状态变化: \(state)")

            switch state {
            case .playing:
                print("开始播放，可以显示播放控制UI")
            case .error(let error):
                print("播放错误: \(error)")
                // 可以显示错误提示给用户
            case .connecting:
                print("连接中，可以显示加载指示器")
            default:
                break
            }
        }
    }
}

// MARK: - 高级用法示例

class AdvancedUsageViewController: UIViewController {

    private var rtmpPlayer: RTMPPlayerViewController!
    private var connectionTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupAdvancedPlayer()
    }

    private func setupAdvancedPlayer() {
        rtmpPlayer = RTMPPlayerViewController()

        // 高级配置
        rtmpPlayer.enableAutoReconnect = true

        // 监控连接状态
        rtmpPlayer.playbackStateDidChange = { [weak self] state in
            self?.handleAdvancedStateChange(state)
        }

        addChild(rtmpPlayer)
        view.addSubview(rtmpPlayer.view)
        rtmpPlayer.didMove(toParent: self)

        // 设置全屏布局
        rtmpPlayer.view.frame = view.bounds
        rtmpPlayer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    private func handleAdvancedStateChange(_ state: RTMPPlayerViewController.PlaybackState) {
        switch state {
        case .connecting:
            startConnectionTimeout()
        case .playing:
            stopConnectionTimeout()
            print("播放成功开始")
        case .error(let error):
            stopConnectionTimeout()
            handlePlaybackError(error)
        case .stopped:
            stopConnectionTimeout()
        default:
            break
        }
    }

    private func startConnectionTimeout() {
        // 设置连接超时（30秒）
        connectionTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            print("连接超时，停止播放")
            self?.rtmpPlayer.stop()
        }
    }

    private func stopConnectionTimeout() {
        connectionTimer?.invalidate()
        connectionTimer = nil
    }

    private func handlePlaybackError(_ error: Error) {
        print("播放错误: \(error)")

        // 可以实现自定义错误处理逻辑
        // 例如：显示用户友好的错误信息、尝试备用流等

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            // 5秒后尝试重新播放
            self.rtmpPlayer.restart()
        }
    }
}
#endif