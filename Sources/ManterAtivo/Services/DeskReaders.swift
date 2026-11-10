import AppKit
import CoreGraphics
import Foundation
import ManterAtivoCore

enum DeskReaders {
    static func displays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            let mode = CGDisplayCopyDisplayMode(id)
            let pixelWidth = mode.map { Int($0.pixelWidth) } ?? Int(screen.frame.width)
            let pixelHeight = mode.map { Int($0.pixelHeight) } ?? Int(screen.frame.height)
            let refresh = mode?.refreshRate ?? 0
            return DisplayInfo(
                id: id,
                name: screen.localizedName,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                pointWidth: Int(screen.frame.width),
                pointHeight: Int(screen.frame.height),
                refreshHz: refresh,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0
            )
        }
    }

    static func usb() -> [USBDeviceInfo] {
        let result = Shell.run(
            executable: "/usr/sbin/ioreg",
            arguments: ["-r", "-c", "IOUSBHostDevice", "-k", "USB Product Name", "-d", "1"]
        )
        return USBListing.devices(from: result.stdout)
    }

    static func holders() -> [SleepHolder] {
        let result = Shell.run(executable: "/usr/bin/pmset", arguments: ["-g", "assertions"])
        return AssertionParser.holders(from: result.stdout)
    }

    static func spotlight() -> Bool? {
        let result = Shell.run(executable: "/usr/bin/mdutil", arguments: ["-s", "/"])
        return SpotlightStatus.indexing(from: result.stdout + "\n" + result.stderr)
    }
}
