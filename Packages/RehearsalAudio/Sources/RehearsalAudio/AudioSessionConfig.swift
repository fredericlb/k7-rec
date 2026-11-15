// AudioSessionConfig.swift: the one AVAudioSession setup the recorder, the player and the metronome share.
// What reads wrong: only iOS has a session; on the Mac every call is a no-op so the logic tests run there.

import AVFoundation

public enum AudioSessionConfig {
  /// `.playAndRecord`, so a take can be heard back and a click played while the microphone is open.
  public static func activate() throws {
    #if os(iOS)
    let s = AVAudioSession.sharedInstance()
    try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
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
