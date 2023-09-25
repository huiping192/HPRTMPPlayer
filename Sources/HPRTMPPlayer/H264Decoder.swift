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
  var decodeSession: VTDecompressionSession?
  var formatDescription: CMFormatDescription?
  
  init() {
    // Initialize the decoder
  }
  
  deinit {
    // Clean up the decode session
    if let decodeSession = decodeSession {
      VTDecompressionSessionInvalidate(decodeSession)
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

