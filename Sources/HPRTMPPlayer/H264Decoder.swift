//
//  File.swift
//  
//
//  Created by 郭 輝平 on 2023/09/23.
//
import Foundation
import VideoToolbox
import CoreMedia

class H264Decoder {
  private var decodeSession: VTDecompressionSession?
  private var _formatDescription: CMFormatDescription?

  var formatDescription: CMFormatDescription? {
    return _formatDescription
  }
  
  enum H264DecoderError: Error {
    case invalidVideoHeader
    case formatDescriptionCreationFailed(status: OSStatus)
    case decompressionSessionCreationFailed(status: OSStatus)
    case frameDecodingFailed(status: OSStatus)
    case outputHandlerFailed
    case sampleBufferCreationFailed(status: OSStatus)
  }
  
  init(videoHeader: Data) throws {
    guard let (sps, pps) = extractSPSandPPS(from: videoHeader) else {
      throw H264DecoderError.invalidVideoHeader
    }
    
    guard let formatDescription = createFormatDescription(sps: sps, pps: pps) else {
      throw H264DecoderError.formatDescriptionCreationFailed(status: -1)
    }
    
    try createDecompressionSession(formatDescription)
  }
  
  deinit {
    // Clean up the decode session
    if let decodeSession = decodeSession {
      VTDecompressionSessionInvalidate(decodeSession)
    }
  }
  
  private func extractSPSandPPS(from videoHeader: Data) -> (sps: Data, pps: Data)? {
    // H.264 配置数据格式:
    // [0x17][0x00][0x00, 0x00, 0x00][configRecord...]
    // configRecord格式: [configurationVersion][profile][compatibility][level][lengthSizeMinusOne][SPS data...]
    guard videoHeader.count >= 16 else {
      print("Video header too short: \(videoHeader.count)")
      return nil
    }

    // 跳过配置记录前部 (版本、profile、兼容性、级别、长度大小)，直接查找SPS数量和长度
    let spsCountPosition = 10  // 0x17(1) + 0x00(1) + composition time(3) + config record start(5) = 10
    guard videoHeader.count > spsCountPosition else {
      print("Video header too short for SPS count: \(videoHeader.count)")
      return nil
    }

    let spsCount = videoHeader[spsCountPosition] & 0x1F  // 取低5位
    print("SPS count: \(spsCount)")

    guard spsCount > 0 else {
      print("No SPS found")
      return nil
    }

    // SPS长度位置
    let spsSizePosition = spsCountPosition + 1
    guard videoHeader.count >= spsSizePosition + 2 else {
      print("Video header too short for SPS size: \(videoHeader.count)")
      return nil
    }

    // 读取SPS长度 (big-endian 16位)
    let spsSize = (Int(videoHeader[spsSizePosition]) << 8) | Int(videoHeader[spsSizePosition + 1])
    print("SPS size: \(spsSize)")

    // 检查SPS数据长度
    let spsDataStart = spsSizePosition + 2
    let spsDataEnd = spsDataStart + spsSize
    guard videoHeader.count >= spsDataEnd else {
      print("Video header too short for SPS data: need \(spsDataEnd), have \(videoHeader.count)")
      return nil
    }

    // 提取SPS数据
    let spsData = videoHeader.subdata(in: spsDataStart..<spsDataEnd)

    // PPS数量位置
    let ppsCountPosition = spsDataEnd
    guard videoHeader.count > ppsCountPosition else {
      print("Video header too short for PPS count: \(videoHeader.count)")
      return nil
    }

    let ppsCount = videoHeader[ppsCountPosition]
    print("PPS count: \(ppsCount)")

    guard ppsCount > 0 else {
      print("No PPS found")
      return nil
    }

    // PPS长度位置
    let ppsSizePosition = ppsCountPosition + 1
    guard videoHeader.count >= ppsSizePosition + 2 else {
      print("Video header too short for PPS size: \(videoHeader.count)")
      return nil
    }

    // 读取PPS长度 (big-endian 16位)
    let ppsSize = (Int(videoHeader[ppsSizePosition]) << 8) | Int(videoHeader[ppsSizePosition + 1])
    print("PPS size: \(ppsSize)")

    // 检查PPS数据长度
    let ppsDataStart = ppsSizePosition + 2
    let ppsDataEnd = ppsDataStart + ppsSize
    guard videoHeader.count >= ppsDataEnd else {
      print("Video header too short for PPS data: need \(ppsDataEnd), have \(videoHeader.count)")
      return nil
    }

    // 提取PPS数据
    let ppsData = videoHeader.subdata(in: ppsDataStart..<ppsDataEnd)

    return (sps: spsData, pps: ppsData)
  }
  
  private func createFormatDescription(sps: Data, pps: Data) -> CMFormatDescription? {
    var formatDescription: CMFormatDescription?
    
    let parameterSets: [Data] = [sps, pps]
    let parameterSetPointers = parameterSets.map { (data) -> UnsafePointer<UInt8> in
      return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> UnsafePointer<UInt8> in
        return bytes.bindMemory(to: UInt8.self).baseAddress!
      }
    }
    
    let parameterSetSizes = parameterSets.map { (data) -> Int in
      return data.count
    }
    
    let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault,
                                                                     parameterSetCount: parameterSets.count,
                                                                     parameterSetPointers: parameterSetPointers,
                                                                     parameterSetSizes: parameterSetSizes,
                                                                     nalUnitHeaderLength: 4,
                                                                     formatDescriptionOut: &formatDescription)
    
    if status == noErr {
      return formatDescription
    } else {
      print("Error creating format description: \(status)")
      return nil
    }
  }
  
  private func createDecompressionSession(_ formatDescription: CMFormatDescription) throws {
    self._formatDescription = formatDescription  // Store formatDescription for later use
    
    let videoOutput: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
    
    var status = VTDecompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      formatDescription: formatDescription,
      decoderSpecification: nil,
      imageBufferAttributes: videoOutput as CFDictionary,
      outputCallback: nil,
      decompressionSessionOut: &decodeSession
    )
    
    guard status == noErr else {
      throw H264DecoderError.decompressionSessionCreationFailed(status: status)
    }
    
    var threadCountValue = 1
    status = VTSessionSetProperty(decodeSession!, key: kVTDecompressionPropertyKey_ThreadCount, value:CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &threadCountValue))
    guard status == noErr else {
      throw H264DecoderError.decompressionSessionCreationFailed(status: status)
    }
  }
  
  func decodeSampleBuffer(_ sampleBuffer: CMSampleBuffer, completion: @escaping (CMSampleBuffer?, Error?) -> Void) {
    guard let decodeSession = decodeSession else {
      completion(nil, H264DecoderError.decompressionSessionCreationFailed(status: -1))
      return
    }
    
    var infoFlags = VTDecodeInfoFlags.asynchronous
    let status = VTDecompressionSessionDecodeFrame(
      decodeSession,
      sampleBuffer: sampleBuffer,
      flags: VTDecodeFrameFlags._EnableAsynchronousDecompression,
      infoFlagsOut: &infoFlags
    ) { status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration in
      guard status == noErr else {
        completion(nil, H264DecoderError.frameDecodingFailed(status: status))
        return
      }
      
      guard let imageBuffer = imageBuffer,
            let formatDescription = self._formatDescription else {
        completion(nil, H264DecoderError.outputHandlerFailed)
        return
      }
      
      var sampleBuffer: CMSampleBuffer?
      
      var timingInfo = CMSampleTimingInfo(
        duration: presentationDuration,
        presentationTimeStamp: presentationTimeStamp,
        decodeTimeStamp: CMTime.invalid
      )
      
      let err = CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: imageBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timingInfo,
        sampleBufferOut: &sampleBuffer
      )
      
      if err == noErr, let sampleBuffer = sampleBuffer {
        completion(sampleBuffer, nil)
      } else {
        completion(nil, H264DecoderError.sampleBufferCreationFailed(status: err))
      }
    }
    
    if status != noErr {
      completion(nil, H264DecoderError.frameDecodingFailed(status: status))
    }
  }
}
