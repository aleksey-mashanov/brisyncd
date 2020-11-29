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
	let ddc: DDC
	var brightness: UInt16 = 101
	var contrast: UInt16 = 101
	var config = Config.defaultConfig
	var job = Job()

	init?(_ display: io_service_t) {
		self.display = display
		guard let ddc = try? DDC(display: display) else {
			IOObjectRelease(display)
			return nil
		}
		self.ddc = ddc
	}

	deinit {
		IOObjectRelease(display)
	}

	lazy var name: String = getDisplayName(display) ?? "unknown"

	struct Config {
		let min: Float
		let max: Float
		let gamma: Float
		let contrast: Float?
		let interval: Int

		init(min: Float = 0, max: Float = 1, gamma: Float = 1, contrast: Float? = nil, interval: Int = 50) {
			self.min = min
			self.max = max
			self.gamma = gamma
			self.contrast = contrast
			self.interval = interval
		}

		static var defaultConfig = Config()
	}

	struct Job {
		var mutex = DispatchSemaphore(value: 1)
		var active = false
		var brightness: UInt16?
		var contrast: UInt16?
	}

	func enqueue(brightness: UInt16? = nil, contrast: UInt16? = nil) {
		job.mutex.wait()
		if let brightness = brightness {
			job.brightness = brightness
		}
		if let contrast = contrast {
			job.contrast = contrast
		}
		if !job.active {
			job.active = true
			DispatchQueue.global(qos: .background).async {
				self.process()
			}
		}
		job.mutex.signal()
	}

	func process() {
		let name = self.name
		job.mutex.wait()
		if let brightness = job.brightness {
			job.brightness = nil
			job.mutex.signal()
			ddc.setVCPFeature(.brightness, to: brightness) {
				switch $0 {
				case .success(_):
					os_log("Target display [%{public}s] brightness set to %d%%", type: .info, name, brightness)
				case .failure(let error):
					os_log("Failed to set target display [%{public}s] brightness to %d%%: %{public}s", name, brightness, String(describing: error))
				}
			}
		} else if let contrast = job.contrast {
			job.contrast = nil
			job.mutex.signal()
			ddc.setVCPFeature(.contrast, to: contrast) {
				switch $0 {
				case .success(_):
					os_log("Target display [%{public}s] contrast set to %d%%", type: .info, name, contrast)
				case .failure(let error):
					os_log("Failed to set target display [%{public}s] contrast to %d%%: %{public}s", name, contrast, String(describing: error))
				}
			}
		} else {
			job.active = false
			job.mutex.signal()
			return
		}
		DispatchQueue.global(qos: .background).asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.milliseconds(config.interval)) {
			self.process()
		}
	}

	func set(brightness: Float) {
		var scaledBrightness = (brightness - config.min) / (config.max - config.min)
		if scaledBrightness < 0 {
			scaledBrightness = 0
		} else if scaledBrightness > 1 {
			scaledBrightness = 1
		}
		let newBrightness = UInt16((powf(scaledBrightness, config.gamma) * 100).rounded())
		if newBrightness != self.brightness {
			enqueue(brightness: newBrightness)
			self.brightness = newBrightness
		}

		if let maxContrast = config.contrast {
			let newContrast = UInt16(((brightness < config.min ? maxContrast * (brightness / config.min) : maxContrast) * 100).rounded())
			if newContrast != self.contrast {
				enqueue(contrast: newContrast)
				self.contrast = newContrast
			}
		}
	}
}
