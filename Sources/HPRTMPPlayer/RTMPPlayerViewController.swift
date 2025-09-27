#if canImport(UIKit) && !targetEnvironment(macCatalyst)
import UIKit
import AVFoundation

// iOS版本的RTMP播放器视图控制器
public class RTMPPlayerViewController: UIViewController {

  // MARK: - Public Properties
  public var player: RTMPPlayer {
    return rtmpPlayer
  }

  public var playbackStateDidChange: ((RTMPPlayer.PlaybackState) -> Void)?

  // MARK: - Private Properties
  private let rtmpPlayer: RTMPPlayer
  private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer!

  // MARK: - Initialization
  public init() {
    rtmpPlayer = RTMPPlayer()
    super.init(nibName: nil, bundle: nil)
    setupPlayer()
  }

  required init?(coder: NSCoder) {
    rtmpPlayer = RTMPPlayer()
    super.init(coder: coder)
    setupPlayer()
  }

  // MARK: - Lifecycle
  public override func viewDidLoad() {
    super.viewDidLoad()
    configureDisplayLayer()
  }

  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    sampleBufferDisplayLayer.frame = view.bounds
  }

  public override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    // 当视图消失时自动停止播放以节省资源
    if rtmpPlayer.playbackState == .playing || rtmpPlayer.playbackState == .connecting {
      rtmpPlayer.stop()
    }
  }

  deinit {
    rtmpPlayer.stop()
  }

  // MARK: - Setup
  private func setupPlayer() {
    rtmpPlayer.delegate = self
  }

  private func configureDisplayLayer() {
    sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    sampleBufferDisplayLayer.frame = view.bounds
    sampleBufferDisplayLayer.videoGravity = .resizeAspect
    sampleBufferDisplayLayer.backgroundColor = UIColor.black.cgColor
    view.layer.addSublayer(sampleBufferDisplayLayer)
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
extension RTMPPlayerViewController: RTMPPlayerDelegate {

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
#endif

