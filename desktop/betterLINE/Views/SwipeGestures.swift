import AppKit
import SwiftUI

/// Two-finger horizontal swipes in a conversation, as in Messages: swiping left
/// slides every message over to show its time; swiping right on a bubble far
/// enough starts a reply to it.
struct SwipeTracker: Equatable {
	enum Mode: Equatable {
		case undecided
		/// Mostly vertical: the list scrolls as usual.
		case vertical
		case times
		case reply(String)
	}

	static let timesWidth: CGFloat = 64
	static let replyThreshold: CGFloat = 56
	static let replyLimit: CGFloat = 90

	private(set) var mode: Mode?
	/// Content travel since the gesture began; positive is to the right.
	private(set) var travel: CGFloat = 0

	/// How far the transcript slides left to show times.
	var timesOffset: CGFloat {
		mode == .times ? min(max(-travel, 0), Self.timesWidth) : 0
	}

	/// How far the swiped bubble slides right, with resistance near the limit.
	var replyOffset: CGFloat {
		guard case .reply = mode, travel > 0 else { return 0 }
		return Self.replyLimit * (1 - exp(-travel / Self.replyLimit))
	}

	var replyTarget: String? {
		if case let .reply(id) = mode { return id }
		return nil
	}

	var replyArmed: Bool { replyOffset >= Self.replyThreshold }

	mutating func begin() {
		mode = .undecided
		travel = 0
	}

	/// Feeds one scroll step. Returns true when the step belongs to the swipe
	/// and must not also scroll the list.
	mutating func move(dx: CGFloat, dy: CGFloat, target: String?) -> Bool {
		switch mode {
		case nil, .vertical?:
			return false
		case .undecided?:
			guard abs(dx) + abs(dy) > 0.5 else { return false }
			guard abs(dx) > abs(dy) * 1.2 else {
				mode = .vertical
				return false
			}
			if dx < 0 {
				mode = .times
			} else if let target {
				mode = .reply(target)
			} else {
				mode = .vertical
				return false
			}
			travel = dx
			return true
		case .times?, .reply?:
			travel += dx
			return true
		}
	}

	/// Ends the gesture; returns the message to reply to when the swipe went far enough.
	mutating func end() -> String? {
		defer {
			mode = nil
			travel = 0
		}
		return replyArmed ? replyTarget : nil
	}

	/// Whether the gesture claimed horizontal movement, so trailing momentum
	/// events should be swallowed too.
	var isHorizontal: Bool {
		mode == .times || replyTarget != nil
	}
}

/// The live swipe for one conversation. Rows read it, the list does not, so a
/// swipe only redraws the rows on screen.
@MainActor
@Observable
final class SwipeModel {
	var tracker = SwipeTracker()
	/// Where each bubble on screen is, in the transcript's coordinate space, so a
	/// reply swipe knows which message it started on.
	@ObservationIgnored var frames: [String: CGRect] = [:]
	@ObservationIgnored private var swallowMomentum = false

	nonisolated static let space = "transcript"

	func message(at point: CGPoint) -> String? {
		frames.first { $0.value.contains(point) }?.key
	}

	/// Handles one scroll event at `point` (in the transcript's coordinate space);
	/// returns true when it was a swipe, not a scroll.
	func handle(_ event: NSEvent, at point: CGPoint, replyTarget: (String) -> Bool, onReply: (String) -> Void) -> Bool {
		if !event.momentumPhase.isEmpty { return swallowMomentum }
		switch event.phase {
		case .began:
			tracker.begin()
			swallowMomentum = false
			return false
		case .changed:
			let wasArmed = tracker.replyArmed
			let target = message(at: point).flatMap { replyTarget($0) ? $0 : nil }
			let consumed = tracker.move(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, target: target)
			if tracker.replyArmed, !wasArmed {
				NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
			}
			return consumed
		case .ended, .cancelled:
			swallowMomentum = tracker.isHorizontal
			var reply: String?
			withAnimation(.spring(duration: 0.3)) { reply = tracker.end() }
			if let reply { onReply(reply) }
			return swallowMomentum
		default:
			return false
		}
	}
}

/// Watches trackpad scroll events over the view it backs and hands them, with
/// their position (top-left origin), to `onScroll`, which returns whether it
/// consumed them.
struct ScrollSwipeMonitor: NSViewRepresentable {
	var onScroll: (NSEvent, CGPoint) -> Bool

	func makeNSView(context: Context) -> MonitorView {
		let view = MonitorView()
		view.onScroll = onScroll
		return view
	}

	func updateNSView(_ view: MonitorView, context: Context) {
		view.onScroll = onScroll
	}

	final class MonitorView: NSView {
		var onScroll: ((NSEvent, CGPoint) -> Bool)?
		private var monitor: Any?

		override var isFlipped: Bool { true }

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			if let monitor { NSEvent.removeMonitor(monitor) }
			monitor = nil
			guard window != nil else { return }
			monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
				let consumed = MainActor.assumeIsolated { () -> Bool in
					guard let self, let window = self.window, let onScroll = self.onScroll else { return false }
					// Compare in screen space: an event's own window may be another one, or none.
					let onScreen = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
					let local = self.convert(window.convertPoint(fromScreen: onScreen), from: nil)
					guard self.bounds.contains(local) else { return false }
					return onScroll(event, local)
				}
				return consumed ? nil : event
			}
		}

		override func hitTest(_ point: NSPoint) -> NSView? { nil }
	}
}
