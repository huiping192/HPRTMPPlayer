//
//  File.swift
//  
//
//  Created by 郭 輝平 on 2023/09/23.
//
import Foundation
import VideoToolbox
import CoreMedia


enum H264DecoderError: Error {
  case invalidVideoHeader
}


class H264Decoder {
  var decodeSession: VTDecompressionSession?
  var formatDescription: CMFormatDescription?
  
  init(videoHeader: Data) throws {
    guard let (sps, pps) = extractSPSandPPS(from: videoHeader) else {
      throw H264DecoderError.invalidVideoHeader
    }
    
    guard let formatDescription = createFormatDescription(sps: sps, pps: pps) else {
      throw H264DecoderError.invalidVideoHeader
    }
    
    createDecompressionSession(formatDescription)
  }
  
  deinit {
    // Clean up the decode session
    if let decodeSession = decodeSession {
      VTDecompressionSessionInvalidate(decodeSession)
    }
  }
  
  func extractSPSandPPS(from videoHeader: Data) -> (sps: Data, pps: Data)? {
    // Skip initial bytes and reach where SPS size is stored
    // [0x17][0x00][0x00, 0x00, 0x00][0x01][sps[1], sps[2], sps[3], 0xff][0xe1] = 16 bytes
    let spsSizeStartPosition = 16
    if videoHeader.count < spsSizeStartPosition + 2 {
      return nil
    }
    
    // Read SPS size
    let spsSize = (Int(videoHeader[spsSizeStartPosition]) << 8) | Int(videoHeader[spsSizeStartPosition + 1])
    
    // Extract SPS Data
    let spsData = videoHeader.subdata(in: (spsSizeStartPosition + 2)..<(spsSizeStartPosition + 2 + spsSize))
    
    // Calculate where PPS size is stored in the array, skip SPS size and SPS data
    let ppsSizeStartPosition = spsSizeStartPosition + 2 + spsSize + 1
    
    if videoHeader.count < ppsSizeStartPosition + 2 {
      return nil
    }
    
    // Read PPS size
    let ppsSize = (Int(videoHeader[ppsSizeStartPosition]) << 8) | Int(videoHeader[ppsSizeStartPosition + 1])
    
    // Extract PPS Data
    let ppsData = videoHeader.subdata(in: (ppsSizeStartPosition + 2)..<(ppsSizeStartPosition + 2 + ppsSize))
    
    return (sps: spsData, pps: ppsData)
  }
  
  func createFormatDescription(sps: Data, pps: Data) -> CMFormatDescription? {
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
    
    let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil,
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
  
  func createDecompressionSession(_ formatDescription: CMFormatDescription) {
    self.formatDescription = formatDescription  // Store formatDescription for later use
    
    let videoOutput: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
    
    let status = VTDecompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      formatDescription: formatDescription,
      decoderSpecification: nil,
      imageBufferAttributes: videoOutput as CFDictionary,
      outputCallback: nil,
      decompressionSessionOut: &decodeSession
    )
    
    if status != noErr {
      print("Error creating decompression session")
    }
  }
  
  func decodeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    guard let decodeSession = decodeSession else {
      print("Decode session is not initialized")
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
        print("Error in output handler")
        return
      }
      
      if let imageBuffer = imageBuffer,
         let formatDescription = self.formatDescription {
        
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
          // Now you have a CMSampleBuffer that you can use
          print("Decoded CMSampleBuffer: \(sampleBuffer)")
        }
      }
    }
    
    if status != noErr {
      print("Error decoding frame")
    }
  }
}

