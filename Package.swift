// swift-tools-version:5.2

import PackageDescription

let package = Package(
	name: "brisyncd",
	platforms: [
		.macOS(.v10_13),
	],
	dependencies: [
		.package(url: "https://github.com/aleksey-mashanov/swift-ddc.git", from: "1.0.0"),
		.package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "0.3.0")),
	],
	targets: [
		.target(name: "brisyncd", dependencies: [
			.product(name: "DDC", package: "swift-ddc"),
			.product(name: "ArgumentParser", package: "swift-argument-parser"),
		]),
	]
)
