import Foundation
import DDC
import os.log
import func Darwin.C.powf

class TargetDisplays: PublishTerminateHandler {
	var targets: [io_object_t: TargetDisplay] = [:]

	override var matchClass: String { return "AppleDisplay" }

	override func published(_ display: io_service_t) throws {
		if targets[display] == nil {
			if let target = TargetDisplay(display: display) {
				targets[display] = target
				os_log("Target display found: %{public}s", target.name)
				return
			}
		}
		IOObjectRelease(display)
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
	let gamma: Float = 2
	let min: Float = 0.25
	let max: Float = 0.75
	let normalContrast: UInt16 = 75

	init?(display: io_service_t) {
		guard let framebuffer = Self.framebuffer(forDisplay: display) else {
			return nil
		}
		self.display = display
		self.framebuffer = framebuffer
		guard let ddc = DDC(forFramebuffer: framebuffer) else {
			return nil
		}
		self.ddc = ddc
	}

	deinit {
		IOObjectRelease(framebuffer)
		IOObjectRelease(display)
	}

	lazy var name: String = getName() ?? "unknown"

	func set(brightness: Float) {
		var scaledBrightness = (brightness - min) / (max - min)
		if scaledBrightness < 0 {
			scaledBrightness = 0
		} else if scaledBrightness > 1 {
			scaledBrightness = 1
		}
		let newBrightness = UInt16(powf(scaledBrightness, gamma) * 100)
		if newBrightness != self.brightness {
			guard ddc.write(command: .brightness, value: newBrightness) else {
				os_log("Failed to set target display [%{public}s] brightness to %d%%", name, newBrightness)
				return
			}
			os_log("Target display [%{public}s] brightness set to %d%%", type: .info, name, newBrightness)
			self.brightness = newBrightness
		}

		let contrast = brightness < min ? UInt16(Float(normalContrast) * (brightness / min)) : normalContrast
		if contrast != self.contrast {
			guard ddc.write(command: .contrast, value: contrast) else {
				os_log("Failed to set target display [%{public}s] contrast to %d%%", name, contrast)
				return
			}
			os_log("Target display [%{public}s] contrast set to %d%%", type: .info, name, contrast)
			self.contrast = contrast
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
