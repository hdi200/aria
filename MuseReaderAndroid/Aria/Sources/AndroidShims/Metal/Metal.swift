// Android stand-in for Metal: there is no Metal device, so the shared code takes its
// Core Graphics / Core Image paths (the video export's compositor falls back).
@_exported import Foundation

public protocol MTLDevice: AnyObject {}

public func MTLCreateSystemDefaultDevice() -> (any MTLDevice)? {
    nil
}
