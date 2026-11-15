// TimeFormat.swift: the clock and the dates of format.ts, the locale always the app's and passed in.
// What reads wrong: an unreadable date prints empty, and a clock below zero or not finite prints 0:00.

import Foundation

/// Seconds as H:MM:SS, or M:SS under an hour.
public func fmtTime(_ totalSec: Double) -> String {
  let t = totalSec.isFinite && totalSec >= 0 ? totalSec : 0
  let s = Int(t.truncatingRemainder(dividingBy: 60))
  let m = Int((t / 60).truncatingRemainder(dividingBy: 60))
  let h = Int(t / 3600)
  let ss = s < 10 ? "0\(s)" : "\(s)"
  if h > 0 { return "\(h):\(m < 10 ? "0\(m)" : "\(m)"):\(ss)" }
  return "\(m):\(ss)"
}

public enum DateStyle: Sendable {
  case day, date, dateTime, stamp, time, timeSeconds
}

/// `at` in the named style and the app's language (a BCP 47 tag).
public func formatDate(_ at: Date, _ style: DateStyle, locale: Locale) -> String {
  let f = DateFormatter()
  f.locale = locale
  switch style {
  case .day: f.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
  case .date: f.dateStyle = .medium
  case .dateTime:
    f.dateStyle = .medium
    f.timeStyle = .short
  case .stamp: f.setLocalizedDateFormatFromTemplate("dMMMjmm")
  case .time: f.setLocalizedDateFormatFromTemplate("jmm")
  case .timeSeconds: f.setLocalizedDateFormatFromTemplate("jmmss")
  }
  return f.string(from: at)
}

/// An ISO 8601 string in the named style; an unreadable one prints empty.
public func formatDate(iso: String, _ style: DateStyle, locale: Locale) -> String {
  let a = ISO8601DateFormatter()
  a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  guard let d = a.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
  return formatDate(d, style, locale: locale)
}

/// A stamp of `d`, as a resumed take's note says when it went on.
public func fmtStamp(locale: Locale, _ d: Date = Date()) -> String { formatDate(d, .stamp, locale: locale) }

/// A take's title: it has no name, so its recording date and time.
public func takeTitle(iso: String, locale: Locale) -> String { formatDate(iso: iso, .stamp, locale: locale) }
