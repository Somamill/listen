import AVFoundation
import MediaToolbox

/// Per-player PCM gain; never changes the system volume. Float output is peak limited.
final class VolumeBoost {
  final class Context {
    let gain: Float
    var floatPCM = false
    init(_ gain: Float) { self.gain = gain }
  }
  static func process(_ pointer: UnsafeMutablePointer<Float>, count: Int, gain: Float) {
    for i in 0..<count { pointer[i] = max(-1, min(1, pointer[i] * gain)) }
  }
  static func mix(track: AVAssetTrack, gain: Float = 2) throws -> AVAudioMix {
    let retained = Unmanaged.passRetained(Context(gain))
    var callbacks = MTAudioProcessingTapCallbacks(
      version: kMTAudioProcessingTapCallbacksVersion_0, clientInfo: retained.toOpaque(),
      init: { _, info, storage in storage.pointee = info },
      finalize: { tap in
        Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
      },
      prepare: { tap, _, format in
        let context = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
          .takeUnretainedValue()
        context.floatPCM =
          format.pointee.mBitsPerChannel == 32
          && format.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
      }, unprepare: nil,
      process: { tap, frames, flags, buffers, framesOut, flagsOut in
        let result = MTAudioProcessingTapGetSourceAudio(
          tap, frames, buffers, flagsOut, nil, framesOut)
        guard result == noErr else {
          framesOut.pointee = 0
          return
        }
        let context = Unmanaged<Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
          .takeUnretainedValue()
        guard context.floatPCM else { return }
        for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
          guard let data = buffer.mData else { continue }
          VolumeBoost.process(
            data.assumingMemoryBound(to: Float.self),
            count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size, gain: context.gain)
        }
      })
    var output: MTAudioProcessingTap?
    let status = MTAudioProcessingTapCreate(
      kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &output)
    guard status == noErr, let tap = output else {
      retained.release()
      throw ListenError.message("Volume boost could not be configured for this audio.")
    }
    let parameters = AVMutableAudioMixInputParameters(track: track)
    parameters.audioTapProcessor = tap
    let mix = AVMutableAudioMix()
    mix.inputParameters = [parameters]
    return mix
  }
}
