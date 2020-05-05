import Foundation
import os.log
import ArgumentParser

struct Brisyncd: ParsableCommand {
	static let configuration = CommandConfiguration(
		abstract: "Synchronize brightnesses of external displays with a main display.",
		discussion: """
			This daemon (user agent) can be used to synchronize the brightness of an external \
			display with a main (integrated) display. \
			This is especially useful if the brightness of your main display is automatically \
			controlled by an ambient light sensor (Macbook Pro, for example).

			brisyncd receives notifications from the system about displays connection/disconnection \
			and automatically selects display to get the brightness from and displays to apply \
			the brightness to.
			"""
	)

	@Option(
		help: ArgumentHelp(
			"Name of the source display.",
			discussion: """
				If not set then the first found will be used.

				"""
		)
	)
	var source: String?

	@OptionGroup()
	var target: Target

	@Option(
		default: [:],
		help: ArgumentHelp(
			"Targets displays configuration for a heterogenous multi-monitor setup.",
			discussion: """
				If you have more than one external display then different configurations \
				may be required for them. In this case you can use this option to \
				configure each monitor separately.

				This option accepts JSON containing a dictionary which keys are names of \
				displays and values are configuration dictionaries with the following \
				keys: "min", "max", "gamma", "contrast". Meaning and possible values are \
				the same as for the command-line options with the same names. \
				Values specified in command-line options in this case are used as defaults.

				Example: '{"DELL U2720Q":{"min":25,"max":75,"gamma":2,"contrast":75}}'

				"""
		),
		transform: {
			guard let data = $0.data(using: .utf8) else {
				throw ValidationError("Badly encoded string, should be UTF-8")
			}
			return try JSONDecoder().decode(Dictionary<String, TargetJSON>.self, from: data)
		}
	)
	var targets: [String: TargetJSON]

	@Flag(
		help: ArgumentHelp(
			"Synchronize brightness of known displays only.",
			discussion: """
				If this flag is set then the brightness of the displays specified in \
				'--targets' option only will be synchronized.

				"""
		)
	)
	var targetsOnly: Bool

	struct Target: ParsableArguments {
		@Option(
			default: 0,
			help: ArgumentHelp(
				"Minimum synchronizable brightness.",
				discussion: """
					Minimum brightness level of the source display which can be represented by the target display.

					To choose the correct value set your target display brightness to 0% and find \
					a value of the source display brightness which looks the same way. \
					If your target display is darker than the source then this value can be lower than 0.

					"""
			)
		)
		var min: Int

		@Option(
			default: 100,
			help: ArgumentHelp(
				"Maximum synchronizable brightness.",
				discussion: """
					Maximum brightness level of the source display which can be represented by the target display.

					To choose the correct value set your target display brightness to 100% and find \
					a value of the source display brightness which looks the same way. \
					If your target display is brighter than the source then this value can be greater than 100.

					"""
			)
		)
		var max: Int

		@Option(
			default: 1,
			help: ArgumentHelp(
				"Gamma correction",
				discussion: """
					Power of the gamma correction function between brightnesses of source and target displays.

					Select this value after '--min' and '--max' if the visible brightnesses of your displays \
					differ in the middle range.

					"""
			)
		)
		var gamma: Float

		@Option(
			help: ArgumentHelp(
				"Contrast of a target display.",
				discussion: """
					Use this option if your target display is not dark enough at brightness 0. \
					If set then will be used while the target display brightness is greater than 0. \
					When the target display brightness reaches 0 then the following darkening of the target \
					display will be performed by lowering the contrast.

					"""
			)
		)
		var contrast: Int?

		mutating func validate() throws {
			guard min < max else {
				throw ValidationError("'max' must be greater then 'min'")
			}

			guard contrast == nil || contrast! >= 0 && contrast! <= 100 else {
				throw ValidationError("'contrast' must be between 0 and 100")
			}
		}
	}

	struct TargetJSON: Codable {
		let min: Int?
		let max: Int?
		let gamma: Float?
		let contrast: Int?
	}

	func run() throws {
		TargetDisplay.Config.defaultConfig = TargetDisplay.Config(target)

		let targets = try TargetDisplays(self.targets.mapValues(TargetDisplay.Config.init), onlyKnown: targetsOnly)
		let sources = try SourceDisplays(name: source) {
			targets.set(brightness: $0)
		}
		try sources.sync()

		let done = DispatchSemaphore(value: 0)

		let sigint = DispatchSource.makeSignalSource(signal: SIGINT)
		sigint.setEventHandler {
			os_log("SIGINT received, terminating", type: .debug)
			done.signal()
		}
		sigint.activate()

		let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM)
		sigterm.setEventHandler {
			os_log("SIGTERM received, terminating", type: .debug)
			done.signal()
		}
		sigterm.activate()

		withExtendedLifetime((sources, targets)) {
			done.wait()
		}
	}
}

Brisyncd.main()

extension TargetDisplay.Config {
	init(_ target: Brisyncd.Target) {
		self.init(
			min: Float(target.min) / 100,
			max: Float(target.max) / 100,
			gamma: target.gamma,
			contrast: target.contrast.map { Float($0) / 100 }
		)
	}

	init(_ target: Brisyncd.TargetJSON) {
		self.init(
			min: target.min.map { Float($0) / 100 } ?? Self.defaultConfig.min,
			max: target.max.map { Float($0) / 100 } ?? Self.defaultConfig.max,
			gamma: target.gamma ?? Self.defaultConfig.gamma,
			contrast: target.contrast.map { Float($0) / 100 } ?? Self.defaultConfig.contrast
		)
	}
}
