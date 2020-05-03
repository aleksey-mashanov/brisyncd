import Foundation

run()

func run() {
	let brisync = try! BrightnessSync()
	try! brisync.sources.sync()

	withExtendedLifetime(sync) {
		DispatchSemaphore(value: 0).wait()
	}
}

struct BrightnessSync {
	let sources: SourceDisplays
	let targets: TargetDisplays

	init() throws {
		let targets = try TargetDisplays()
		sources = try SourceDisplays() {
			targets.set(brightness: $0)
		}
		self.targets = targets
	}
}
