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
    private var synchronizer: AVSampleBufferRenderSynchronizer!
    private var audioRenderer: AVSampleBufferAudioRenderer!

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
        synchronizer?.setRate(0.0, time: CMTime.zero)
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
        
        // 配置音频会话
        configureAudioSession()
        
        // 创建 AVSampleBufferRenderSynchronizer
        synchronizer = AVSampleBufferRenderSynchronizer()
        
        // 创建音频渲染器
        audioRenderer = AVSampleBufferAudioRenderer()
        
        // 将视频层和音频渲染器添加到同步器
        synchronizer.addRenderer(sampleBufferDisplayLayer)
        synchronizer.addRenderer(audioRenderer)
        
        // 设置播放速率
        synchronizer.setRate(1.0, time: CMTime.zero)
        
        print("AVSampleBufferRenderSynchronizer 配置成功")
        
        layer.addSublayer(sampleBufferDisplayLayer)
    }
    
    private func configureAudioSession() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetooth])
            print("音频会话配置成功")
        } catch {
            print("音频会话配置失败: \(error)")
        }
#else
        // macOS 不需要音频会话配置
        print("macOS 音频配置完成")
#endif
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
        // 设置同步器播放速率
        synchronizer.setRate(1.0, time: CMTime.zero)
        rtmpPlayer.play(rtmpURLString)
    }

    public func stop() {
        synchronizer.setRate(0.0, time: CMTime.zero)
        rtmpPlayer.stop()
    }

    public func pause() {
        synchronizer.setRate(0.0, time: CMTime.zero)
        rtmpPlayer.pause()
    }

    public func resume() {
        synchronizer.setRate(1.0, time: CMTime.zero)
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
    private func enqueueVideo(sampleBuffer: CMSampleBuffer) {
        if sampleBufferDisplayLayer.isReadyForMoreMediaData {
            sampleBufferDisplayLayer.enqueue(sampleBuffer)
        }
    }
    
    private func enqueueAudio(sampleBuffer: CMSampleBuffer) {
        if audioRenderer.isReadyForMoreMediaData {
            audioRenderer.enqueue(sampleBuffer)
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
            self.enqueueVideo(sampleBuffer: sampleBuffer)
        }
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didReceiveAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async {
            self.enqueueAudio(sampleBuffer: sampleBuffer)
        }
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
            self.audioRenderer.flush()
            // 重置同步器
            self.synchronizer.setRate(0.0, time: CMTime.zero)
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
    private var audioRenderer: AVSampleBufferAudioRenderer!
    private var synchronizer: AVSampleBufferRenderSynchronizer!
    private var isSynchronizerStarted = false  // 标记同步器是否已启动
    private var firstFramePTS: CMTime?  // 记录第一帧（视频或音频）的 PTS

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
        synchronizer?.setRate(0.0, time: CMTime.zero)
        // 移除音频渲染器观察者
        audioRenderer?.removeObserver(self, forKeyPath: "status")
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

        // 配置音频会话
        configureAudioSession()

        // 创建同步器和音频渲染器
        synchronizer = AVSampleBufferRenderSynchronizer()
        audioRenderer = AVSampleBufferAudioRenderer()

        // macOS 音频渲染器配置
        configureAudioRenderer()

        // 将视频层和音频渲染器都添加到同步器（完全同步）
        synchronizer.addRenderer(sampleBufferDisplayLayer)
        synchronizer.addRenderer(audioRenderer)

        print("macOS 音视频同步器配置完成")

        layer?.addSublayer(sampleBufferDisplayLayer)
    }
    
    private func configureAudioSession() {
        // macOS 不需要音频会话配置
        print("macOS 音频配置完成")
      
      
    }
    
    private func configureAudioRenderer() {
        // macOS 音频渲染器配置
        audioRenderer.volume = 1.0
        audioRenderer.isMuted = false

        // 设置音频渲染器状态监听
        audioRenderer.addObserver(self, forKeyPath: "status", options: [.new], context: nil)

        // 配置回调机制：当渲染器准备接收更多数据时通知
        audioRenderer.requestMediaDataWhenReady(on: DispatchQueue.main) { [weak self] in
            // 渲染器准备好接收更多数据时，这个闭包会被调用
            // 这样可以避免在未就绪时强制入队导致的问题
        }

        print("macOS 音频渲染器配置完成 - 音量: \(audioRenderer.volume), 静音: \(audioRenderer.isMuted)")

        // 打印系统音频信息
        printSystemAudioInfo()
    }

    private func printSystemAudioInfo() {
        print("[Audio Init] 音频渲染器初始化完成")
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let audioRenderer = object as? AVSampleBufferAudioRenderer {
                print("音频渲染器状态: \(audioRenderer.status.rawValue)")
                switch audioRenderer.status {
                case .unknown:
                    print("音频渲染器状态: 未知")
                case .rendering:
                    print("音频渲染器状态: 渲染中")
                case .failed:
                    print("音频渲染器状态: 失败 - \(audioRenderer.error?.localizedDescription ?? "未知错误")")
                @unknown default:
                    print("音频渲染器状态: 其他")
                }
            }
        }
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
        // 激活音频会话
        activateAudioSession()
        rtmpPlayer.play(rtmpURLString)
    }

    public func stop() {
        synchronizer.setRate(0.0, time: CMTime.zero)
        isSynchronizerStarted = false
        firstFramePTS = nil
        rtmpPlayer.stop()
        // 停用音频会话
        deactivateAudioSession()
    }

    public func pause() {
        rtmpPlayer.pause()
    }

    public func resume() {
        // 重新激活音频会话
        activateAudioSession()
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
    private func enqueueVideo(sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // 记录第一帧 PTS（视频或音频，谁先到用谁的）
        if firstFramePTS == nil {
            firstFramePTS = pts
            print("[Video Sync] 第一帧视频 PTS: \(CMTimeGetSeconds(pts))s")
        }

        // 入队视频帧（同步器会自动管理播放速率和缓冲）
        sampleBufferDisplayLayer.enqueue(sampleBuffer)

        // 首帧触发：启动同步器
        if !isSynchronizerStarted {
            startSynchronizerWithFirstFrame()
            isSynchronizerStarted = true
        }
    }
    
    private func enqueueAudio(sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // 记录第一帧 PTS（视频或音频，谁先到用谁的）
        if firstFramePTS == nil {
            firstFramePTS = pts
            print("[Audio Sync] 第一帧音频 PTS: \(CMTimeGetSeconds(pts))s")
        }

        // 入队音频帧（同步器会自动管理播放速率和缓冲）
        audioRenderer.enqueue(sampleBuffer)

        // 首帧触发：启动同步器
        if !isSynchronizerStarted {
            startSynchronizerWithFirstFrame()
            isSynchronizerStarted = true
        }

        // 错误检测
        if let error = audioRenderer.error {
            print("[Audio Error] \(error.localizedDescription)")
        }
    }

    /// 启动同步器：从第一帧的 PTS 开始播放
    /// 无论是视频还是音频先到，都用第一帧的 PTS 启动同步器
    /// 这样同步器知道"当前时间"是第一帧的时间，而不是 0
    private func startSynchronizerWithFirstFrame() {
        guard let firstPTS = firstFramePTS else { return }

        // 让同步器从第一帧的 PTS 开始播放
        // 例如：如果第一帧是 29 秒，同步器会认为"现在是 29 秒"，立即播放
        synchronizer.setRate(1.0, time: firstPTS)

        print("[Sync Started] 同步器从 \(CMTimeGetSeconds(firstPTS))s 开始播放")
    }
    
    private func activateAudioSession() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            print("音频会话激活成功")
        } catch {
            print("音频会话激活失败: \(error)")
        }
#else
        // macOS 不需要激活音频会话
        print("macOS 音频会话激活完成")
#endif
    }
    
    private func deactivateAudioSession() {
#if canImport(UIKit) && !targetEnvironment(macCatalyst)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("音频会话停用成功")
        } catch {
            print("音频会话停用失败: \(error)")
        }
#else
        // macOS 不需要停用音频会话
        print("macOS 音频会话停用完成")
#endif
    }
}

// MARK: - RTMPPlayerDelegate
extension RTMPPlayerView: RTMPPlayerDelegate {

    public func rtmpPlayer(_ player: RTMPPlayer, didChangeState state: RTMPPlayer.PlaybackState) {
        DispatchQueue.main.async {
            self.playbackStateDidChange?(state)

            // 根据播放状态激活或停用音频会话
            switch state {
            case .playing:
                self.activateAudioSession()
                print("macOS播放器状态: 播放中 - 音频会话已激活")
            case .paused, .stopped, .idle:
                self.deactivateAudioSession()
                print("macOS播放器状态: \(state) - 音频会话已停用")
            case .connecting:
                print("macOS播放器状态: 连接中")
            case .error(let error):
                print("macOS播放器状态: 错误 - \(error)")
            }
        }
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didReceiveVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async {
            self.enqueueVideo(sampleBuffer: sampleBuffer)
        }
    }

    public func rtmpPlayer(_ player: RTMPPlayer, didReceiveAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        DispatchQueue.main.async {
            self.enqueueAudio(sampleBuffer: sampleBuffer)
        }
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
            self.audioRenderer.flush()
            self.synchronizer.setRate(0.0, time: CMTime.zero)
            self.isSynchronizerStarted = false
            self.firstFramePTS = nil
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
