import Foundation

@MainActor
enum Format {
	private static let locale = Locale(identifier: "zh_Hant_TW")

	private static func formatter(_ template: String) -> DateFormatter {
		let f = DateFormatter()
		f.locale = locale
		f.setLocalizedDateFormatFromTemplate(template)
		return f
	}

	private static let clock: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "HH:mm"
		return f
	}()
	private static let weekday = formatter("EEEE")
	private static let monthDay = formatter("MMMdEEEE")
	private static let fullDay = formatter("yyyyMMMdEEEE")
	private static let shortDate = formatter("M/d")
	private static let shortFullDate = formatter("yyyy/M/d")
	private static let dateTime = formatter("yyyyMMMd HH:mm")

	static func time(_ date: Date) -> String {
		clock.string(from: date)
	}

	/// Chat list: 14:05, 昨天, 星期二, 9/28, 2025/9/28.
	static func listTime(_ date: Date, now: Date = .now) -> String {
		let cal = Calendar.current
		if cal.isDateInToday(date) { return clock.string(from: date) }
		if cal.isDateInYesterday(date) { return "昨天" }
		if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day, days < 7 {
			return weekday.string(from: date)
		}
		if cal.isDate(date, equalTo: now, toGranularity: .year) { return shortDate.string(from: date) }
		return shortFullDate.string(from: date)
	}

	/// The day part of a conversation's time header: 今天, 昨天, 星期二, 10月3日 星期六.
	static func day(_ date: Date, now: Date = .now) -> String {
		let cal = Calendar.current
		if cal.isDateInToday(date) { return "今天" }
		if cal.isDateInYesterday(date) { return "昨天" }
		if let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day, days < 7 {
			return weekday.string(from: date)
		}
		if cal.isDate(date, equalTo: now, toGranularity: .year) { return monthDay.string(from: date) }
		return fullDay.string(from: date)
	}

	/// 9/28, or 2025/9/28 outside the current year.
	static func date(_ date: Date, now: Date = .now) -> String {
		Calendar.current.isDate(date, equalTo: now, toGranularity: .year) ? shortDate.string(from: date) : shortFullDate.string(from: date)
	}

	static func dateTime(_ date: Date) -> String {
		dateTime.string(from: date)
	}

	static func duration(ms: Int) -> String {
		let total = max(0, ms / 1000)
		return String(format: "%d:%02d", total / 60, total % 60)
	}

	static func bytes(_ count: Int64) -> String {
		ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
	}
}

/// Search folding that matches the server's: Traditional and Simplified
/// Chinese compare equal, and case and width are ignored.
enum TextFold {
	private static let toSimplified = StringTransform("Hant-Hans")

	static func fold(_ text: String) -> String {
		let simplified = text.applyingTransform(toSimplified, reverse: false) ?? text
		return simplified.precomposedStringWithCompatibilityMapping.lowercased()
	}

	static func matches(_ text: String, query: String) -> Bool {
		let q = fold(query.trimmingCharacters(in: .whitespaces))
		return q.isEmpty || fold(text).contains(q)
	}
}
