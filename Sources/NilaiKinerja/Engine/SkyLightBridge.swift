import AppKit
import Darwin

/// Floats a window above every other window, including the notch surface and
/// lock-screen overlays.
///
/// SkyLight is a private framework. Every symbol is resolved with `dlsym` at
/// runtime and guarded — if macOS drops or renames one, `isAvailable` goes
/// false and callers fall back to a plain `.statusBar` window. The app must
/// still work after an OS update, just with worse z-ordering.
@MainActor
final class SkyLightBridge {
    static let shared = SkyLightBridge()

    /// Highest level the window server accepts. Used by the system's own
    /// notch surface, so our window sits in the same plane as the hardware cutout.
    private static let notchSurfaceLevel: Int32 = 2_147_483_647

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias CopyManagedSpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private let connection: Int32
    private let surfaceSpace: Int32
    private let addWindows: AddWindows?
    private let copyManagedSpaces: CopyManagedSpaces?

    private init() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

        guard let handle = dlopen(path, RTLD_NOW) else {
            NSLog("[SkyLight] dlopen failed for \(path)")
            connection = 0
            surfaceSpace = 0
            addWindows = nil
            copyManagedSpaces = nil
            return
        }

        guard
            let mainID = dlsym(handle, "SLSMainConnectionID"),
            let create = dlsym(handle, "SLSSpaceCreate"),
            let setLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let show = dlsym(handle, "SLSShowSpaces"),
            let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            NSLog("[SkyLight] required symbol missing — falling back to statusBar level")
            connection = 0
            surfaceSpace = 0
            addWindows = nil
            copyManagedSpaces = nil
            return
        }

        let conn = unsafeBitCast(mainID, to: MainConnectionID.self)()
        let space = unsafeBitCast(create, to: SpaceCreate.self)(conn, 1, 0)
        if space != 0 {
            _ = unsafeBitCast(setLevel, to: SpaceSetAbsoluteLevel.self)(
                conn, space, Self.notchSurfaceLevel
            )
            _ = unsafeBitCast(show, to: ShowSpaces.self)(conn, [space] as CFArray)
        }

        let copySym = dlsym(handle, "CGSCopyManagedDisplaySpaces")
            ?? dlsym(handle, "SLSCopyManagedDisplaySpaces")

        connection = conn
        surfaceSpace = space
        addWindows = unsafeBitCast(add, to: AddWindows.self)
        copyManagedSpaces = copySym.map { unsafeBitCast($0, to: CopyManagedSpaces.self) }
    }

    var isAvailable: Bool { connection != 0 && surfaceSpace != 0 && addWindows != nil }

    /// Attaches `window` to the notch surface plane. Returns false when the
    /// private API is unavailable so the caller can keep the window usable
    /// at a lower level.
    @discardableResult
    func attach(_ window: NSWindow) -> Bool {
        guard let addWindows, isAvailable else { return false }
        let result = addWindows(
            connection,
            surfaceSpace,
            [window.windowNumber] as CFArray,
            7
        )
        return result != 0
    }

    /// True when `screen` is currently showing a fullscreen space. Used to
    /// suppress the checkpoint so it never appears over someone's presentation.
    func isFullscreenSpaceActive(on screen: NSScreen) -> Bool {
        // SkyLight keys spaces by display *UUID string*, not by the numeric
        // display id, so the comparison must use the UUID.
        guard let copyManagedSpaces,
              let uuid = screen.displayUUID,
              let managed = copyManagedSpaces(connection)?.takeRetainedValue() as? [[String: Any]],
              let entry = managed.first(where: { dict in
                  guard let id = dict["Display Identifier"] as? String else { return false }
                  return id.caseInsensitiveCompare(uuid) == .orderedSame
              }),
              let currentSpace = entry["Current Space"] as? [String: Any],
              let type = currentSpace["type"] as? NSNumber
        else { return false }

        return type.intValue == 4
    }
}

extension NSScreen {
    var cgDisplayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var displayUUID: String? {
        guard let id = cgDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
        else { return nil }
        return (CFUUIDCreateString(nil, uuid) as String).uppercased()
    }
}
