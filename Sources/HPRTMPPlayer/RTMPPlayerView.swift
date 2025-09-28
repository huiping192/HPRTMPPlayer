#if canImport(UIKit) && !targetEnvironment(macCatalyst)
import UIKit
import AVFoundation

// iOS版本的RTMP播放器视图
public class RTMPPlayerView: UIView {

    // MARK: - Public Properties
    public var player: RTMPPlayer {
        return rtmpPlayer
    }

    public var playbackStateDidChange: ((RTMPPlayer.PlaybackState) -> Void)?

    // MARK: - Private Properties
    private let rtmpPlayer: RTMPPlayer
    private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer!
    private var lifecycleObserver: RTMPPlayerLifecycleObserver?

    // MARK: - Initialization
    public override init(frame: CGRect) {
        rtmpPlayer = RTMPPlayer()
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        rtmpPlayer = RTMPPlayer()
        super.init(coder: coder)
        setupView()
    }

    deinit {
        rtmpPlayer.stop()
        lifecycleObserver = nil
    }

    // MARK: - Setup
    private func setupView() {
        backgroundColor = UIColor.black
        configureDisplayLayer()
        setupPlayerDelegate()
        setupLifecycleObserver()
    }

    private func configureDisplayLayer() {
        sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
        sampleBufferDisplayLayer.frame = bounds
        sampleBufferDisplayLayer.videoGravity = .resizeAspect
        sampleBufferDisplayLayer.backgroundColor = UIColor.black.cgColor
        layer.addSublayer(sampleBufferDisplayLayer)
    }

    private func setupPlayerDelegate() {
        rtmpPlayer.delegate = self
    }

    private func setupLifecycleObserver() {
        lifecycleObserver = RTMPPlayerLifecycleObserver(rtmpPlayer: rtmpPlayer)
    }

    // MARK: - Layout
    public override func layoutSubviews() {
        super.layoutSubviews()
        sampleBufferDisplayLayer.frame = bounds
    }

    // MARK: - Public Methods
    public func play(_ rtmpURLString: String) {
        rtmpPlayer.play(rtmpURLString)
    }

    public func stop() {
        rtmpPlayer.stop()
    }

    public func pause() {
        rtmpPlayer.pause()
    }

    public func resume() {
        rtmpPlayer.resume()
    }

    public func restart() {
        rtmpPlayer.restart()
    }

    public func enablePerformanceMonitoring() {
        rtmpPlayer.enablePerformanceMonitoring()
    }

    public func getPerformanceStats() -> PerformanceMonitor.PlaybackStats {
        return rtmpPlayer.getPerformanceStats()
    }

    // MARK: - Private Methods
    private func enqueue(sampleBuffer: CMSampleBuffer) {
        if sampleBufferDisplayLayer.isReadyForMoreMediaData {
            sampleBufferDisplayLayer.enqueue(sampleBuffer)
        }
    }
}

// MARK: - RTMPPlayerDelegate
extension RTMPPlayerView: RTMPPlayerDelegate {

    public func rtmpPlayer(_ player: RTMPPlayer, didChangeState state: RTMPPlayer.PlaybackState) {
        DispatchQueue.main.async {
            self.playbackStateDidChange?(state)
        }
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didReceiveVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async {
            self.enqueue(sampleBuffer: sampleBuffer)
        }
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didReceiveAudioData data: Data, timestamp: Int64) {
        // 音频数据处理（已在核心播放器中处理）
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didReceiveVideoConfiguration config: VideoConfiguration) {
        DispatchQueue.main.async {
            print("iOS播放器收到视频配置: \(config.width)x\(config.height)")
        }
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didUpdateStatistics statistics: Any) {
        DispatchQueue.main.async {
            print("iOS播放器统计更新: \(statistics)")
        }
    }

    public func rtmpPlayerDidCleanupResources(_ player: RTMPPlayer) {
        DispatchQueue.main.async {
            self.sampleBufferDisplayLayer.flushAndRemoveImage()
        }
    }
}

// MARK: - iOS生命周期观察者
private class RTMPPlayerLifecycleObserver {
    private weak var rtmpPlayer: RTMPPlayer?

    init(rtmpPlayer: RTMPPlayer) {
        self.rtmpPlayer = rtmpPlayer
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        guard let player = rtmpPlayer else { return }
        if player.playbackState == .playing || player.playbackState == .connecting {
            player.stop()
        }
    }

    @objc private func appWillEnterForeground() {
        // 可以在这里实现重新连接逻辑，如果需要的话
    }
}

#elseif canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import AVFoundation

// macOS版本的RTMP播放器视图
public class RTMPPlayerView: NSView {

    // MARK: - Public Properties
    public var player: RTMPPlayer {
        return rtmpPlayer
    }

    public var playbackStateDidChange: ((RTMPPlayer.PlaybackState) -> Void)?

    // MARK: - Private Properties
    private let rtmpPlayer: RTMPPlayer
    private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer!

    // MARK: - Initialization
    public override init(frame frameRect: NSRect) {
        rtmpPlayer = RTMPPlayer()
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        rtmpPlayer = RTMPPlayer()
        super.init(coder: coder)
        setupView()
    }

    deinit {
        rtmpPlayer.stop()
    }

    // MARK: - Setup
    private func setupView() {
        wantsLayer = true

        configureDisplayLayer()
        setupPlayerDelegate()
    }

    private func configureDisplayLayer() {
        sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
        sampleBufferDisplayLayer.frame = bounds
        sampleBufferDisplayLayer.videoGravity = .resizeAspect
        sampleBufferDisplayLayer.backgroundColor = NSColor.black.cgColor

        layer?.addSublayer(sampleBufferDisplayLayer)
    }

    private func setupPlayerDelegate() {
        rtmpPlayer.delegate = self
    }

    // MARK: - Layout
    public override func layout() {
        super.layout()
        sampleBufferDisplayLayer.frame = bounds
    }

    public override var isFlipped: Bool {
        return true
    }

    // MARK: - Public Methods
    public func play(_ rtmpURLString: String) {
        rtmpPlayer.play(rtmpURLString)
    }

    public func stop() {
        rtmpPlayer.stop()
    }

    public func pause() {
        rtmpPlayer.pause()
    }

    public func resume() {
        rtmpPlayer.resume()
    }

    public func restart() {
        rtmpPlayer.restart()
    }

    public func enablePerformanceMonitoring() {
        rtmpPlayer.enablePerformanceMonitoring()
    }

    public func getPerformanceStats() -> PerformanceMonitor.PlaybackStats {
        return rtmpPlayer.getPerformanceStats()
    }

    // MARK: - Private Methods
    private func enqueue(sampleBuffer: CMSampleBuffer) {
        if sampleBufferDisplayLayer.isReadyForMoreMediaData {
            sampleBufferDisplayLayer.enqueue(sampleBuffer)
        }
    }
}

// MARK: - RTMPPlayerDelegate
extension RTMPPlayerView: RTMPPlayerDelegate {

    public func rtmpPlayer(_ player: RTMPPlayer, didChangeState state: RTMPPlayer.PlaybackState) {
        DispatchQueue.main.async {
            self.playbackStateDidChange?(state)
        }
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didReceiveVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async {
            self.enqueue(sampleBuffer: sampleBuffer)
        }
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didReceiveAudioData data: Data, timestamp: Int64) {
        // 音频数据处理（已在核心播放器中处理）
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didReceiveVideoConfiguration config: VideoConfiguration) {
        DispatchQueue.main.async {
            print("macOS播放器收到视频配置: \(config.width)x\(config.height)")
        }
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didUpdateStatistics statistics: Any) {
        DispatchQueue.main.async {
            print("macOS播放器统计更新: \(statistics)")
        }
    }

    public func rtmpPlayerDidCleanupResources(_ player: RTMPPlayer) {
        DispatchQueue.main.async {
            self.sampleBufferDisplayLayer.flushAndRemoveImage()
        }
    }
}

// MARK: - macOS特定的播放器窗口控制器
public class RTMPPlayerWindowController: NSWindowController {

    private var rtmpPlayerView: RTMPPlayerView!

    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RTMP播放器"
        window.center()

        self.init(window: window)
        setupPlayerView()
    }

    private func setupPlayerView() {
        rtmpPlayerView = RTMPPlayerView()
        rtmpPlayerView.translatesAutoresizingMaskIntoConstraints = false

        window?.contentView = rtmpPlayerView

        // 设置状态变化回调
        rtmpPlayerView.playbackStateDidChange = { [weak self] state in
            self?.updateWindowTitle(for: state)
        }
    }

    private func updateWindowTitle(for state: RTMPPlayer.PlaybackState) {
        DispatchQueue.main.async {
            switch state {
            case .idle:
                self.window?.title = "RTMP播放器 - 空闲"
            case .connecting:
                self.window?.title = "RTMP播放器 - 连接中..."
            case .playing:
                self.window?.title = "RTMP播放器 - 播放中"
            case .paused:
                self.window?.title = "RTMP播放器 - 已暂停"
            case .stopped:
                self.window?.title = "RTMP播放器 - 已停止"
            case .error(let error):
                self.window?.title = "RTMP播放器 - 错误: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Public Methods
    public func play(_ rtmpURLString: String) {
        rtmpPlayerView.play(rtmpURLString)
    }

    public func stop() {
        rtmpPlayerView.stop()
    }

    public func pause() {
        rtmpPlayerView.pause()
    }

    public func resume() {
        rtmpPlayerView.resume()
    }

    public func enablePerformanceMonitoring() {
        rtmpPlayerView.enablePerformanceMonitoring()
    }
}

#endif