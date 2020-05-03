import Foundation
import os.log

class SourceDisplays: PublishTerminateHandler {
	let callback: (Float) -> Void
	var source: SourceDisplay?

	override var matchClass: String { return "AppleBacklightDisplay" }

	init(_ callback: @escaping (Float) -> Void) throws {
		self.callback = callback
		try super.init()
	}

	func sync() throws {
		try source?.sync()
	}

	override func published(_ service: io_service_t) throws {
		guard self.source == nil else {
			IOObjectRelease(service)
			return
		}
		source = try SourceDisplay(service, callback)
		os_log("Source display found: %{public}s", source!.name)
	}

	override func terminated(_ service: io_service_t) throws {
		if source?.display == service {
			os_log("Source display gone: %{public}s", source!.name)
			source = nil
		}
		IOObjectRelease(service)
	}
}

class SourceDisplay: Display {
	let display: io_service_t
	let port: IONotificationPortRef
	var notification: io_object_t = 0
	var brightness: Float = 0
	let callback: (Float) -> Void

	init(_ service: io_service_t, _ callback: @escaping (Float) -> Void) throws {
		self.display = service
		self.callback = callback
		guard let port = IONotificationPortCreate(kIOMasterPortDefault) else {
			IOObjectRelease(service)
			throw BrightnessSyncError.ioNotificationPortCreate
		}
		IONotificationPortSetDispatchQueue(port, DispatchQueue.global(qos: .background))
		self.port = port
		guard IOServiceAddInterestNotification(port, service, kIOGeneralInterest, sourceCallback, Unmanaged.passUnretained(self).toOpaque(), &notification) == KERN_SUCCESS else {
			IONotificationPortDestroy(port)
			IOObjectRelease(service)
			throw BrightnessSyncError.ioServiceAddInterestNotification
		}
	}

	deinit {
		IOObjectRelease(notification)
		IONotificationPortDestroy(port)
		IOObjectRelease(display)
	}

	lazy var name: String = getName() ?? "unknown"

	func sync() throws {
		var brightness: Float = 0
		guard IODisplayGetFloatParameter(display, 0, kIODisplayBrightnessKey as CFString, &brightness) == KERN_SUCCESS else {
			throw BrightnessSyncError.getBrightnessFailed
		}
		guard brightness != self.brightness else {
			return
		}
		os_log("Source display [%{public}s] brightness: %.2f%%", type: .debug, name, brightness * 100)
		callback(brightness)
		self.brightness = brightness
	}
}

func sourceCallback(_ refcon: UnsafeMutableRawPointer!, _ service: io_service_t, _ messageType: UInt32, _ messageArgument: UnsafeMutableRawPointer?) {
	do {
		try Unmanaged<SourceDisplay>.fromOpaque(refcon).takeUnretainedValue().sync()
	} catch {
		os_log("Failed to handle source display notification: %s", String(describing: error))
	}
}
