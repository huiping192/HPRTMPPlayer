# RTMP播放器实现TODO

## 项目现状分析
- ✅ H264Decoder 已实现 (支持SPS/PPS解析和VideoToolbox解码)
- ✅ RTMPPlayerViewController 基础结构已创建 (AVSampleBufferDisplayLayer)
- ✅ HPRTMP库的RTMPPlayerSession 已可用
- ❌ 各组件间未连接，缺少完整播放流程

## 核心实现任务

### 1. 连接RTMP核心功能
- [ ] 在RTMPPlayerViewController中集成RTMPPlayerSession
- [ ] 实现RTMPPlayerSessionDelegate协议
- [ ] 完善play方法启动RTMP连接
- [ ] 添加状态管理和错误处理

### 2. 视频解码集成
- [ ] 在收到视频metadata时初始化H264Decoder
- [ ] 处理RTMP视频数据流送入解码器
- [ ] 连接解码器输出到AVSampleBufferDisplayLayer
- [ ] 处理时间戳同步

### 3. 播放控制和状态管理
- [ ] 实现播放/暂停/停止功能
- [ ] 添加连接状态反馈
- [ ] 优化内存管理和资源释放
- [ ] 错误恢复机制

### 4. 测试验证
- [ ] 创建基本播放测试用例
- [ ] 测试不同RTMP流格式
- [ ] 性能优化和调试

## 预期结果
完成后将拥有一个可以播放RTMP流的完整播放器，支持H.264视频解码和实时显示。