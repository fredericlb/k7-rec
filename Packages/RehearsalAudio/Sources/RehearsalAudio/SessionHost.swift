// SessionHost.swift: the audio session behind a protocol, so interruptions are testable on the Mac (docs/audio.md).
// What reads wrong: an interruption ending never resumes anything; only the caller's explicit resume does.

import AVFoundation

public enum InterruptionEvent: Sendable, Equatable {
  case began
  case ended(shouldResume: Bool)
  /// The media services daemon restarted: every engine and session object must be rebuilt.
  case mediaServicesReset
}

public protocol SessionHost: AnyObject, Sendable {
  var onInterruption: (@Sendable (InterruptionEvent) -> Void)? { get set }
  func observe()
  func unobserve()
  func activate(recording: Bool, headsetInput: Bool) throws
}

/// The device's AVAudioSession; on the Mac there is no session, so it observes nothing and activates nothing.
public final class SystemSession: SessionHost, @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@Sendable (InterruptionEvent) -> Void)?
  private var tokens: [NSObjectProtocol] = []

  public init() {}

  public var onInterruption: (@Sendable (InterruptionEvent) -> Void)? {
    get { lock.withLock { handler } }
    set { lock.withLock { handler = newValue } }
  }

  public func observe() {
    #if os(iOS)
    unobserve()
    let center = NotificationCenter.default
    let session = AVAudioSession.sharedInstance()
    let interruption = center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] n in
      self?.onInterruption?(Self.event(from: n.userInfo))
    }
    let reset = center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
      self?.onInterruption?(.mediaServicesReset)
    }
    lock.withLock { tokens = [interruption, reset] }
    #endif
  }

  public func unobserve() {
    let old = lock.withLock { () -> [NSObjectProtocol] in
      defer { tokens = [] }
      return tokens
    }
    for t in old { NotificationCenter.default.removeObserver(t) }
  }

  public func activate(recording: Bool, headsetInput: Bool) throws {
    try AudioSessionConfig.activate(recording: recording, headsetInput: headsetInput)
  }

  #if os(iOS)
  private static func event(from info: [AnyHashable: Any]?) -> InterruptionEvent {
    let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt
    guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return .began }
    let flags = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
    return .ended(shouldResume: flags.contains(.shouldResume))
  }
  #endif
}

/// A notification token a main-actor object can drop from its nonisolated deinit.
final class ObserverToken: @unchecked Sendable {
  private var token: NSObjectProtocol?
  func set(_ t: NSObjectProtocol) { token = t }
  func remove() {
    if let t = token { NotificationCenter.default.removeObserver(t) }
    token = nil
  }
  deinit { remove() }
}
