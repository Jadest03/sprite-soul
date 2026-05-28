import Foundation
import CoreGraphics
import ScreenCaptureKit
import ImageIO

guard CommandLine.arguments.count >= 2 else { print("USAGE_ERROR"); exit(1) }
let outputPath = CommandLine.arguments[1]

if !CGPreflightScreenCaptureAccess() {
    CGRequestScreenCaptureAccess()
    print("PERMISSION_NEEDED")
    exit(2)
}

let sema = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            print("NO_DISPLAY"); exitCode = 3; sema.signal(); return
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let url = URL(fileURLWithPath: outputPath)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            print("DEST_FAILED"); exitCode = 4; sema.signal(); return
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            print("FINALIZE_FAILED"); exitCode = 5; sema.signal(); return
        }
        print("OK")
    } catch {
        print("ERROR: \(error)"); exitCode = 6
    }
    sema.signal()
}

sema.wait()
exit(exitCode)
