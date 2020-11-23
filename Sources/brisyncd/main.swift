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

			Additional configuration can be provided by a configuration file. \
			By default brisyncd reads configuration from ~/.brisyncd.json and /usr/local/etc/brisyncd.json \
			(the first found of them). This can be overridden by --config option. \
			\(configHelpHeader)

			See `brisyncd help config` for more information.
			""",
		subcommands: [ConfigCommand.self]
	)

	static let configHelpHeader = """
		Configuration file is a JSON with the following structure (all fields are optional, comments here \
		are for readability, they must be omitted in the config file):

		{
			"source": "Color LCD",  # name of the source display
			"min": 0,               # default minimum brightness level (default: 0)
			"max": 100,             # default maximum brightness level (default: 100)
			"gamma": 1.0,           # default brightness gamma correction (default: 1.0)
			"contrast": null,       # default contrast (default: null)
			"interval": 50,         # default update interval, ms. (default: 50)
			"targets": {            # dictionary of targets with custom configuration
				"DELL U2720Q": {    # keys of the dict are names of the target displays
					"min": 35,      # minimum brightness level
					"max": 85,      # maximum brightness level
					"gamma": 2.2,   # brightness gamma correction
					"contrast": 75, # normal contrast
					"interval": 50  # update interval, ms.
				}
			},
			"targetsOnly": true     # manage known targets only (default: false)
		}
		"""

	struct Options: ParsableArguments {
		@Option(
			name: .shortAndLong,
			help: "Read a configuration from the file <config>."
		)
		var config: String?

		@Option(help: .hidden)
		var source: String?

		@Option(
			help: .hidden,
			transform: {
				guard let data = $0.data(using: .utf8) else {
					throw ValidationError("Badly encoded string, should be UTF-8")
				}
				return try JSONDecoder().decode(Dictionary<String, Config.Target>.self, from: data)
			}
		)
		var targets: [String: Config.Target]?

		@Flag(help: .hidden)
		var targetsOnly: Bool = false

		@Option(help: .hidden)
		var min: Int?

		@Option(help: .hidden)
		var max: Int?

		@Option(help: .hidden)
		var gamma: Float?

		@Option(help: .hidden)
		var contrast: Int?

		@Option(help: .hidden)
		var interval: Int?
	}

	@OptionGroup()
	var options: Options

	static func initDisplays(with config: Config) throws -> (SourceDisplays, TargetDisplays) {
		TargetDisplay.Config.defaultConfig = TargetDisplay.Config(config)

		let targets = try TargetDisplays(config.targets.mapValues(TargetDisplay.Config.init), onlyKnown: config.targetsOnly)
		let sources = try SourceDisplays(name: config.source) {
			targets.set(brightness: $0)
		}
		return (sources, targets)
	}

	func run() throws {
		let config = try Config.read(with: options)
		let (sources, targets) = try Brisyncd.initDisplays(with: config)
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

	struct ConfigCommand: ParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "config",
			abstract: "Print current configuration to stdout.",
			discussion: """
				The starting point of a configuration customization. \
				Run `brisyncd config -o ~/.brisyncd.json` and then edit \
				the generated file.

				\(configHelpHeader)

				TOP LEVEL PARAMETERS

				* "source"
				A name of the source display. \
				If not set then the first found will be used.

				* "targets"
				Targets displays configuration for a heterogenous multi-monitor setup. \
				If you have more than one external display then different configurations \
				may be required for them. In this case you can use this option to \
				configure each monitor separately.
				This option must be a dictionary which keys are names of \
				displays and values are configuration dictionaries with the following \
				keys: "min", "max", "gamma", "contrast" and "interval".
				See "TARGET DISPLAY PARAMETERS" section below.

				* "targetsOnly"
				Synchronize brightness of known displays only. \
				If this flag is set then the brightness of the displays specified in \
				"targets" key only will be synchronized.

				* "min", "max", "gamma", "contrast", "interval"
				Default values for the parameters described in "TARGET DISPLAY PARAMETERS".

				TARGET DISPLAY PARAMETERS

				* "min" (default: 0)
				Minimum brightness level of the source display which can be represented by the target display.
				To choose the correct value set your target display brightness to 0% and find \
				a value of the source display brightness which looks the same way. \
				If your target display is darker than the source then this value can be lower than 0.

				* "max" (default: 100)
				Maximum brightness level of the source display which can be represented by the target display.
				To choose the correct value set your target display brightness to 100% and find \
				a value of the source display brightness which looks the same way. \
				If your target display is brighter than the source then this value can be greater than 100.

				* "gamma" (default: 1.0)
				Power of the gamma correction function between brightnesses of source and target displays.
				Select this value after "min" and "max" if the visible brightnesses of your displays \
				differ in the middle range.

				* "contrast"
				Contrast of a target display.
				Use this option if your target display is not dark enough at brightness 0. \
				If set then will be used while the target display brightness is greater than 0. \
				When the target display brightness reaches 0 then the following darkening of the target \
				display will be performed by lowering the contrast.

				* "interval" (default: 50)
				Target display update interval, ms.
				This option is used to not DoS display's DDC/CI by sending too many messages to it. \
				Increment interval if you encounter problems.
				"""
		)

		@OptionGroup()
		var options: Options

		@Option(name: .shortAndLong, help: "A file to write the current configuration to.")
		var output: String?

		func run() throws {
			var config = try Config.read(with: options)
			let (sources, targets) = try Brisyncd.initDisplays(with: config)
			config.source = sources.source?.name
			for target in targets.targets.values {
				config.targets[target.name] = Config.Target(target.config)
			}

			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

			var data = try encoder.encode(config)
			data.append(contentsOf: "\n".utf8)
			if let output = output {
				try data.write(to: URL(fileURLWithPath: output))
			} else {
				FileHandle.standardOutput.write(data)
			}
		}
	}
}

Brisyncd.main()

protocol TargetConfig {
	var min: Int? { get set }
	var max: Int? { get set }
	var gamma: Float? { get set }
	var contrast: Int? { get set }
	var interval: Int? { get set }
	init(min: Int?, max: Int?, gamma: Float?, contrast: Int?, interval: Int?)
}

extension TargetDisplay.Config {
	init(_ target: TargetConfig) {
		self.init(
			min: target.min.map { Float($0) / 100 } ?? Self.defaultConfig.min,
			max: target.max.map { Float($0) / 100 } ?? Self.defaultConfig.max,
			gamma: target.gamma ?? Self.defaultConfig.gamma,
			contrast: target.contrast.map { Float($0) / 100 } ?? Self.defaultConfig.contrast,
			interval: target.interval ?? Self.defaultConfig.interval
		)
	}
}

struct Config: Codable, TargetConfig {
	var min: Int?
	var max: Int?
	var gamma: Float?
	var contrast: Int?
	var interval: Int?

	var source: String? = nil
	var targets: [String: Target] = [:]
	var targetsOnly = false

	init(min: Int? = nil, max: Int? = nil, gamma: Float? = nil, contrast: Int? = nil, interval: Int? = nil) {
		self.min = min
		self.max = max
		self.gamma = gamma
		self.contrast = contrast
		self.interval = interval
	}

	struct Target: Codable, TargetConfig {
		var min: Int?
		var max: Int?
		var gamma: Float?
		var contrast: Int?
		var interval: Int?
	}

	static func read(from file: String) throws -> Config {
		let expandedFile = NSString(string: file).expandingTildeInPath
		do {
			let data = try Data(contentsOf: URL(fileURLWithPath: expandedFile))
			return try JSONDecoder().decode(Self.self, from: data)
		} catch let error as CocoaError {
			throw Error.configNotFound(expandedFile, error.localizedDescription)
		} catch let error as DecodingError {
			throw Error.configCorrupted(expandedFile, String(describing: error))
		}
	}

	static func read() throws -> Config? {
		for file in ["~/.brisyncd.json", "/usr/local/etc/brisyncd.json"] {
			do {
				return try read(from: file)
			} catch Error.configNotFound {
			}
		}
		return nil
	}

	static func read(with options: Brisyncd.Options) throws -> Config {
		var c = try options.config.map(Config.read(from:)) ?? Config.read() ?? Config()
		if let source = options.source {
			c.source = source
		}
		if let targets = options.targets {
			c.targets = targets
		}
		if options.targetsOnly {
			c.targetsOnly = true
		}
		if let min = options.min {
			c.min = min
		}
		if let max = options.max {
			c.max = max
		}
		if let gamma = options.gamma {
			c.gamma = gamma
		}
		if let contrast = options.contrast {
			c.contrast = contrast
		}
		if let interval = options.interval {
			c.interval = interval
		}
		return c
	}

	enum Error: Swift.Error, CustomStringConvertible {
		case configNotFound(String, String)
		case configCorrupted(String, String)

		var description: String {
			switch self {
			case .configNotFound(let file, let msg):
				return "Failed to read config file [\(file)]: \(msg)"
			case .configCorrupted(let file, let msg):
				return "Failed to parse config file [\(file)]: \(msg)"
			}
		}
	}
}

extension TargetConfig {
	init(_ target: TargetDisplay.Config) {
		self.init(
			min: Int(target.min * 100),
			max: Int(target.max * 100),
			gamma: target.gamma,
			contrast: target.contrast.map { Int($0 * 100) },
			interval: target.interval
		)
	}
}
