# HPRTMPPlayer

一个基于Swift的RTMP流媒体播放器，支持H.264视频解码和实时播放。

## 功能特性

### 🎥 视频播放
- ✅ RTMP协议支持
- ✅ H.264视频解码（使用VideoToolbox）
- ✅ 实时视频渲染（AVSampleBufferDisplayLayer）
- ✅ SPS/PPS参数自动解析
- ✅ NALU格式转换

### 🎮 播放控制
- ✅ 播放/暂停/停止控制
- ✅ 状态管理和回调
- ✅ 自动重连机制（最多3次）
- ✅ 连接超时处理

### 🔊 音频支持
- ✅ 基础音频解码框架
- ⚠️ 简化实现（演示用途）
- 🔄 可扩展为完整AAC解码

### 📊 性能监控
- ✅ FPS监控
- ✅ 丢帧统计
- ✅ 内存使用监控
- ✅ 播放统计信息

### 🛡️ 错误处理
- ✅ 完整的错误传播链
- ✅ 自动重连策略
- ✅ 资源自动清理
- ✅ 内存泄漏防护

## 快速开始

### 基本用法

```swift
import HPRTMPPlayer

class ViewController: UIViewController {
    private var rtmpPlayer: RTMPPlayerViewController!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPlayer()
    }

    private func setupPlayer() {
        rtmpPlayer = RTMPPlayerViewController()

        // 设置状态回调
        rtmpPlayer.playbackStateDidChange = { state in
            switch state {
            case .playing:
                print("开始播放")
            case .error(let error):
                print("播放错误: \(error)")
            default:
                break
            }
        }

        // 添加到视图
        addChild(rtmpPlayer)
        view.addSubview(rtmpPlayer.view)
        rtmpPlayer.didMove(toParent: self)

        // 开始播放
        rtmpPlayer.play("rtmp://your-rtmp-server.com/live/stream")
    }
}
```

## 核心API

### 播放控制方法
- `play(_ url: String)` - 开始播放RTMP流
- `stop()` - 停止播放
- `pause()` - 暂停播放
- `resume()` - 恢复播放
- `restart()` - 重新播放当前流

### 状态管理
```swift
enum PlaybackState {
    case idle          // 空闲
    case connecting    // 连接中
    case playing       // 播放中
    case paused        // 暂停
    case stopped       // 停止
    case error(Error)  // 错误
}
```

## 架构设计

RTMP播放器采用模块化设计，核心组件包括：

1. **RTMPPlayerViewController** - 主控制器
2. **H264Decoder** - 视频解码器
3. **AudioDecoder/AudioPlayer** - 音频处理（简化版）
4. **PerformanceMonitor** - 性能监控

## 支持的功能

- [x] RTMP流播放
- [x] H.264硬件解码
- [x] 自动重连
- [x] 性能监控
- [x] 内存管理
- [ ] 完整音频支持
- [ ] HLS支持

## 示例代码

查看 `Examples/BasicUsage.swift` 获取完整使用示例。