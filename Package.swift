// swift-tools-version: 5.10
import PackageDescription
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
#if arch(arm64)
let hostArchitecture = "arm64"
#else
let hostArchitecture = "x86_64"
#endif
let package = Package(
    name: "Paper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Paper", targets: ["Paper"])],
    targets: [
        .target(name: "CPDFEngine", publicHeadersPath: "include",
                cSettings: [.unsafeFlags(["-I\(root)/Vendor/mupdf/include"])],
                linkerSettings: [.unsafeFlags(["-L\(root)/Vendor/mupdf/build/\(hostArchitecture)-release", "-lmupdf", "-lmupdf-third"]), .linkedLibrary("c++"), .linkedLibrary("z"), .linkedFramework("CoreFoundation")]),
        .target(name: "PaperCore", dependencies: ["CPDFEngine"], linkerSettings: [.linkedFramework("PDFKit"), .linkedFramework("Vision")]),
        .executableTarget(name: "Paper", dependencies: ["PaperCore"], linkerSettings: [.linkedFramework("AppKit")]),
        .testTarget(name: "PaperCoreTests", dependencies: ["PaperCore", "CPDFEngine"])
    ]
)
