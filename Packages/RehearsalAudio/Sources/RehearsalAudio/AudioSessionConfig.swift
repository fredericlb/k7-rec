// AudioSessionConfig.swift: the one AVAudioSession setup the recorder, the player and the metronome share.
// What reads wrong: only iOS has a session; on the Mac every call is a no-op so the logic tests run there.

import AVFoundation

public enum AudioSessionConfig {
  /// `.playAndRecord`; Bluetooth is A2DP, and the hands-free profile only for a take that wants the headset's microphone.
  public static func activate(recording: Bool = false, headsetInput: Bool = false) throws {
    #if os(iOS)
    let s = AVAudioSession.sharedInstance()
    var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP]
    if recording && headsetInput { options.insert(.allowBluetoothHFP) }
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
