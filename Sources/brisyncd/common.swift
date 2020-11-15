import Foundation
import os.log

enum BrightnessSyncError: Error, CustomStringConvertible {
	case serviceNotFound
	case ioNotificationPortCreate
	case ioServiceAddInterestNotification
	case ioServiceAddMatchingNotification
	case getBrightnessFailed

	var description: String {
		switch self {
		case .serviceNotFound:
			return "Service AppleBacklightDisplay not found"
		case .ioNotificationPortCreate:
			return "IONotificationPortCreate failed"
		case .ioServiceAddInterestNotification:
			return "IOServiceAddInterestNotification failed"
		case .ioServiceAddMatchingNotification:
			return "IOServiceAddMatchingNotification failed"
		case .getBrightnessFailed:
			return "Get display brightness failed"
		}
	}
}

class PublishTerminateHandler {
	let port: IONotificationPortRef
	var published: io_object_t = 0
	var terminated: io_object_t = 0

	var matchClass: String { return "IODisplay" }

	init() throws {
		guard let port = IONotificationPortCreate(kIOMasterPortDefault) else {
			throw BrightnessSyncError.ioNotificationPortCreate
		}
		IONotificationPortSetDispatchQueue(port, DispatchQueue.global(qos: .background))
		self.port = port

		let matching = IOServiceMatching(matchClass)
		let selfRef = Unmanaged.passUnretained(self).toOpaque()
		guard IOServiceAddMatchingNotification(port, kIOPublishNotification, matching, publishedCallback, selfRef, &published) == KERN_SUCCESS else {
			IONotificationPortDestroy(port)
			throw BrightnessSyncError.ioServiceAddMatchingNotification
		}
		guard IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching, terminatedCallback, selfRef, &terminated) == KERN_SUCCESS else {
			IOObjectRelease(published)
			IONotificationPortDestroy(port)
			throw BrightnessSyncError.ioServiceAddMatchingNotification
		}

		publishedCallback(selfRef, published)
		terminatedCallback(selfRef, terminated)
	}

	deinit {
		IOObjectRelease(terminated)
		IOObjectRelease(published)
		IONotificationPortDestroy(port)
	}

	func published(_ service: io_service_t) throws {
		IOObjectRelease(service)
	}

	func terminated(_ service: io_service_t) throws {
		IOObjectRelease(service)
	}
}

func publishedCallback(_ refcon: UnsafeMutableRawPointer!, _ iterator: io_iterator_t) {
	let handler = Unmanaged<PublishTerminateHandler>.fromOpaque(refcon).takeUnretainedValue()
	while case let service = IOIteratorNext(iterator), service != 0 {
		do {
			try handler.published(service)
		} catch {
			os_log("Failed to handle display publishing: %s", String(describing: error))
		}
	}
}

func terminatedCallback(_ refcon: UnsafeMutableRawPointer!, _ iterator: io_iterator_t) {
	let handler = Unmanaged<PublishTerminateHandler>.fromOpaque(refcon).takeUnretainedValue()
	while case let service = IOIteratorNext(iterator), service != 0 {
		do {
			try handler.terminated(service)
		} catch {
			os_log("Failed to handle display termination: %s", String(describing: error))
		}
	}
}

protocol Display {
	var display: io_service_t { get }
	var name: String { get set }
}

func getDisplayName(_ display: io_service_t) -> String? {
	let info = IODisplayCreateInfoDictionary(display, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary
	guard let names = info[kDisplayProductName] as? NSDictionary else {
		return nil
	}
	guard let first = names.allKeys.first, let name = names[first] else {
		return nil
	}
	return name as? String
}
