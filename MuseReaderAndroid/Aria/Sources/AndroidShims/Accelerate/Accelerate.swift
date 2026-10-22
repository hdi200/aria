// Android stand-in for Accelerate: the vDSP and BLAS routines the shared playback code
// uses, as plain loops (the compiler vectorizes them).
@_exported import Foundation

public typealias vDSP_Length = UInt
public typealias vDSP_Stride = Int

/// C = max(|A|)
public func vDSP_maxmgv(_ a: UnsafePointer<Float>, _ strideA: vDSP_Stride, _ c: UnsafeMutablePointer<Float>, _ count: vDSP_Length) {
    var peak: Float = 0
    for index in 0..<Int(count) {
        peak = max(peak, abs(a[index * strideA]))
    }
    c.pointee = peak
}

/// C = 0
public func vDSP_vclr(_ c: UnsafeMutablePointer<Float>, _ strideC: vDSP_Stride, _ count: vDSP_Length) {
    for index in 0..<Int(count) {
        c[index * strideC] = 0
    }
}

/// C = A + B
public func vDSP_vadd(_ a: UnsafePointer<Float>, _ strideA: vDSP_Stride,
                      _ b: UnsafePointer<Float>, _ strideB: vDSP_Stride,
                      _ c: UnsafeMutablePointer<Float>, _ strideC: vDSP_Stride, _ count: vDSP_Length) {
    for index in 0..<Int(count) {
        c[index * strideC] = a[index * strideA] + b[index * strideB]
    }
}

/// D = A * b + C
public func vDSP_vsma(_ a: UnsafePointer<Float>, _ strideA: vDSP_Stride, _ b: UnsafePointer<Float>,
                      _ c: UnsafePointer<Float>, _ strideC: vDSP_Stride,
                      _ d: UnsafeMutablePointer<Float>, _ strideD: vDSP_Stride, _ count: vDSP_Length) {
    let scalar = b.pointee
    for index in 0..<Int(count) {
        d[index * strideD] = a[index * strideA] * scalar + c[index * strideC]
    }
}

/// Y = X
public func cblas_scopy(_ count: Int32, _ x: UnsafePointer<Float>, _ strideX: Int32,
                        _ y: UnsafeMutablePointer<Float>, _ strideY: Int32) {
    for index in 0..<Int(count) {
        y[index * Int(strideY)] = x[index * Int(strideX)]
    }
}

/// Darwin's math module has Float overloads; Android's only takes Double.
public func log10(_ value: Float) -> Float {
    Float(Foundation.log10(Double(value)))
}

// MARK: - vImage (the video export's photo background blur)

public typealias vImagePixelCount = UInt
public typealias vImage_Flags = UInt32
public typealias vImage_Error = Int
public let kvImageNoFlags: vImage_Flags = 0
public let kvImageEdgeExtend: vImage_Flags = 8
public let kvImageNoError: vImage_Error = 0
public let kvImageInvalidParameterCombination: vImage_Error = -21_789

public struct vImage_Buffer {
    public var data: UnsafeMutableRawPointer?
    public var height: vImagePixelCount
    public var width: vImagePixelCount
    public var rowBytes: Int

    public init(data: UnsafeMutableRawPointer?, height: vImagePixelCount, width: vImagePixelCount, rowBytes: Int) {
        self.data = data
        self.height = height
        self.width = width
        self.rowBytes = rowBytes
    }
}

/// A box blur of four 8-bit channels with edges extended (the flags the shared code passes):
/// each output pixel is the mean of the kernel around it, rows first, then columns.
public func vImageBoxConvolve_ARGB8888(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                       _ tempBuffer: UnsafeMutableRawPointer?, _ srcOffsetToROI_X: vImagePixelCount,
                                       _ srcOffsetToROI_Y: vImagePixelCount, _ kernel_height: UInt32, _ kernel_width: UInt32,
                                       _ backgroundColor: UnsafePointer<UInt8>?, _ flags: vImage_Flags) -> vImage_Error {
    let source = src.pointee
    let output = dest.pointee
    guard let input = source.data?.assumingMemoryBound(to: UInt8.self),
          let result = output.data?.assumingMemoryBound(to: UInt8.self),
          kernel_width % 2 == 1, kernel_height % 2 == 1
    else { return kvImageInvalidParameterCombination }
    let width = Int(min(source.width, output.width))
    let height = Int(min(source.height, output.height))
    guard width > 0, height > 0 else { return kvImageNoError }
    var rows = [UInt8](repeating: 0, count: width * height * 4)
    rows.withUnsafeMutableBufferPointer { scratch in
        let temp = scratch.baseAddress!
        let horizontal = Int(kernel_width) / 2
        for y in 0..<height {
            boxLine(from: input + y * source.rowBytes, step: 4, count: width, radius: horizontal,
                    to: temp + y * width * 4, outputStep: 4)
        }
        let vertical = Int(kernel_height) / 2
        for x in 0..<width {
            boxLine(from: temp + x * 4, step: width * 4, count: height, radius: vertical,
                    to: result + x * 4, outputStep: output.rowBytes)
        }
    }
    return kvImageNoError
}

/// One row or column of four-channel pixels, `step` bytes apart.
private func boxLine(from line: UnsafePointer<UInt8>, step: Int, count: Int, radius: Int,
                     to output: UnsafeMutablePointer<UInt8>, outputStep: Int) {
    let span = radius * 2 + 1
    var sums = (0, 0, 0, 0)
    func pixel(_ index: Int) -> UnsafePointer<UInt8> { line + min(max(index, 0), count - 1) * step }
    for offset in -radius...radius {
        let p = pixel(offset)
        sums.0 += Int(p[0]); sums.1 += Int(p[1]); sums.2 += Int(p[2]); sums.3 += Int(p[3])
    }
    for index in 0..<count {
        let out = output + index * outputStep
        out[0] = UInt8(sums.0 / span); out[1] = UInt8(sums.1 / span)
        out[2] = UInt8(sums.2 / span); out[3] = UInt8(sums.3 / span)
        let leaving = pixel(index - radius)
        let entering = pixel(index + radius + 1)
        sums.0 += Int(entering[0]) - Int(leaving[0]); sums.1 += Int(entering[1]) - Int(leaving[1])
        sums.2 += Int(entering[2]) - Int(leaving[2]); sums.3 += Int(entering[3]) - Int(leaving[3])
    }
}
