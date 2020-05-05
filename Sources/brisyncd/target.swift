import Foundation
import DDC
import os.log
import func Darwin.C.powf

class TargetDisplays: PublishTerminateHandler {
	var targets: [io_object_t: TargetDisplay] = [:]
	var onlyKnown: Bool = false
	var config: [String: TargetDisplay.Config]

	override var matchClass: String { return "AppleDisplay" }

	init(_ config: [String: TargetDisplay.Config] = [:], onlyKnown: Bool = false) throws {
		self.config = config
		self.onlyKnown = onlyKnown
		try super.init()
	}

	override func published(_ display: io_service_t) throws {
		guard targets[display] == nil else {
			IOObjectRelease(display)
			return
		}
		let cfg = getDisplayName(display).flatMap { config[$0] }
		guard !onlyKnown || cfg != nil else {
			IOObjectRelease(display)
			return
		}
		guard let target = TargetDisplay(display) else {
			return
		}
		if let cfg = cfg {
			target.config = cfg
		}
		targets[display] = target
		os_log("Target display found: %{public}s", target.name)
	}

	override func terminated(_ display: io_service_t) throws {
		if let target = targets.removeValue(forKey: display) {
			os_log("Target display gone: %{public}s", target.name)
		}
		IOObjectRelease(display)
	}

	func set(brightness: Float) {
		for target in targets.values {
			target.set(brightness: brightness)
		}
	}
}

class TargetDisplay: Display {
	let display: io_service_t
	let framebuffer: io_service_t
	let ddc: DDC
	var brightness: UInt16 = 101
	var contrast: UInt16 = 101
	var config = Config.defaultConfig

	init?(_ display: io_service_t) {
		guard let framebuffer = Self.framebuffer(forDisplay: display) else {
			IOObjectRelease(display)
			return nil
		}
		self.display = display
		self.framebuffer = framebuffer
		guard let ddc = DDC(forFramebuffer: framebuffer) else {
			IOObjectRelease(framebuffer)
			IOObjectRelease(display)
			return nil
		}
		self.ddc = ddc
	}

	deinit {
		IOObjectRelease(framebuffer)
		IOObjectRelease(display)
	}

	lazy var name: String = getDisplayName(display) ?? "unknown"

	struct Config {
		let min: Float
		let max: Float
		let gamma: Float
		let contrast: Float?

		init(min: Float = 0, max: Float = 1, gamma: Float = 1, contrast: Float? = nil) {
			self.min = min
			self.max = max
			self.gamma = gamma
			self.contrast = contrast
		}

		static var defaultConfig = Config()
	}

	func set(brightness: Float) {
		var scaledBrightness = (brightness - config.min) / (config.max - config.min)
		if scaledBrightness < 0 {
			scaledBrightness = 0
		} else if scaledBrightness > 1 {
			scaledBrightness = 1
		}
		let newBrightness = UInt16(powf(scaledBrightness, config.gamma) * 100)
		if newBrightness != self.brightness {
			guard ddc.write(command: .brightness, value: newBrightness) else {
				os_log("Failed to set target display [%{public}s] brightness to %d%%", name, newBrightness)
				return
			}
			os_log("Target display [%{public}s] brightness set to %d%%", type: .info, name, newBrightness)
			self.brightness = newBrightness
		}

		if let maxContrast = config.contrast {
			let newContrast = UInt16(100 * (brightness < config.min ? maxContrast * (brightness / config.min) : maxContrast))
			if newContrast != self.contrast {
				guard ddc.write(command: .contrast, value: newContrast) else {
					os_log("Failed to set target display [%{public}s] contrast to %d%%", name, newContrast)
					return
				}
				os_log("Target display [%{public}s] contrast set to %d%%", type: .info, name, newContrast)
				self.contrast = newContrast
			}
		}
	}

	static func framebuffer(forDisplay display: io_service_t) -> io_service_t? {
		var displayConnect: io_service_t = 0
		guard IORegistryEntryGetParentEntry(display, kIOServicePlane, &displayConnect) == KERN_SUCCESS else {
			return nil
		}
		defer { IOObjectRelease(displayConnect) }
		var framebuffer: io_service_t = 0
		guard IORegistryEntryGetParentEntry(displayConnect, kIOServicePlane, &framebuffer) == KERN_SUCCESS else {
			return nil
		}
		return framebuffer
	}
}
