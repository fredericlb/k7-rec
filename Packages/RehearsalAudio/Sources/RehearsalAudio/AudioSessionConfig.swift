// AudioSessionConfig.swift: the one AVAudioSession setup the recorder, the player and the metronome share.
// What reads wrong: only iOS has a session; on the Mac every call is a no-op so the logic tests run there.

import AVFoundation
import Foundation

public enum AudioSessionConfig {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var hfpHeld = false
  nonisolated(unsafe) private static var recordingHeld = false

  /// Whether the session carries the hands-free profile: a headset take asks for it, and what plays meanwhile keeps it.
  static func wantsHFP(recording: Bool, headsetInput: Bool) -> Bool {
    lock.withLock {
      if recording { hfpHeld = headsetInput }
      return hfpHeld
    }
  }

  /// The take ended: the click and playback no longer need the headset's profile.
  public static func endRecording() { lock.withLock { hfpHeld = false; recordingHeld = false } }

  /// `.playAndRecord`; Bluetooth is A2DP, and the hands-free profile only for a take that wants the headset's microphone.
  public static func activate(recording: Bool = false, headsetInput: Bool = false) throws {
    #if os(iOS)
    let s = AVAudioSession.sharedInstance()
    var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP]
    if wantsHFP(recording: recording, headsetInput: headsetInput) { options.insert(.allowBluetoothHFP) }
    #if targetEnvironment(macCatalyst)
    // On the Mac `.playAndRecord` makes the engine report a configuration change as it starts, which stops playback:
    // plain playback uses `.playback`, and a take in progress keeps its category (docs/mac.md).
    let recordingNow = lock.withLock { () -> Bool in
      if recording { recordingHeld = true }
      return recordingHeld
    }
    if !recordingNow {
      try s.setCategory(.playback, mode: .default)
      try s.setActive(true)
      return
    }
    #endif
    try s.setCategory(.playAndRecord, mode: .default, options: options)
    try s.setActive(true)
    #endif
  }

  public static func deactivate() {
    #if os(iOS)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }

  /// Asks for the microphone; true when it may be used.
  public static func requestMicrophone() async -> Bool {
    #if os(iOS)
    return await AVAudioApplication.requestRecordPermission()
    #else
    return true
    #endif
  }
}
