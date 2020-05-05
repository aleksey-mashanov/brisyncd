// swift-tools-version:5.2

import PackageDescription

let package = Package(
	name: "brisyncd",
	platforms: [
		.macOS(.v10_12),
	],
	dependencies: [
		.package(url: "https://github.com/aleksey-mashanov/DDC.swift.git", .branch("master")),
		.package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMinor(from: "0.0.5")),
	],
	targets: [
		.target(name: "brisyncd", dependencies: [
			.product(name: "DDC", package: "DDC.swift"),
			.product(name: "ArgumentParser", package: "swift-argument-parser"),
		]),
	]
)
