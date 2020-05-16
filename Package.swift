// swift-tools-version:5.2

import PackageDescription

let package = Package(
	name: "brisyncd",
	platforms: [
		.macOS(.v10_13),
	],
	dependencies: [
		.package(url: "https://github.com/aleksey-mashanov/DDC.swift.git", .branch("master")),
		.package(url: "https://github.com/apple/swift-argument-parser.git", .branch("master")),
	],
	targets: [
		.target(name: "brisyncd", dependencies: [
			.product(name: "DDC", package: "DDC.swift"),
			.product(name: "ArgumentParser", package: "swift-argument-parser"),
		]),
	]
)
