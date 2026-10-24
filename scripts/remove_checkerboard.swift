import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: remove_checkerboard.swift input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Could not load input image.\n", stderr)
    exit(1)
}

let width = image.width
let height = image.height
let bytesPerRow = width * 4
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("Could not create pixel buffer.\n", stderr)
    exit(1)
}

context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
guard let rawData = context.data else {
    fputs("Could not access pixel buffer.\n", stderr)
    exit(1)
}

let pixels = rawData.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
var foreground = [UInt8](repeating: 0, count: width * height)

for y in 0..<height {
    for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        let red = Int(pixels[offset])
        let green = Int(pixels[offset + 1])
        let blue = Int(pixels[offset + 2])
        let neutral = abs(red - green) <= 4 && abs(green - blue) <= 4
        let checkerboard = neutral && red >= 235
        foreground[y * width + x] = checkerboard ? 0 : 1
    }
}

let radius = 10
var horizontal = [UInt8](repeating: 0, count: width * height)
for y in 0..<height {
    var active = 0
    for x in 0..<width {
        let entering = x + radius
        if entering < width { active += Int(foreground[y * width + entering]) }
        let leaving = x - radius - 1
        if leaving >= 0 { active -= Int(foreground[y * width + leaving]) }
        horizontal[y * width + x] = active > 0 ? 1 : 0
    }
}

var stickerMask = [UInt8](repeating: 0, count: width * height)
for x in 0..<width {
    var active = 0
    for y in 0..<height {
        let entering = y + radius
        if entering < height { active += Int(horizontal[entering * width + x]) }
        let leaving = y - radius - 1
        if leaving >= 0 { active -= Int(horizontal[leaving * width + x]) }
        stickerMask[y * width + x] = active > 0 ? 1 : 0
    }
}

for y in 0..<height {
    for x in 0..<width {
        let pixelIndex = y * width + x
        let offset = y * bytesPerRow + x * 4
        if foreground[pixelIndex] == 1 {
            pixels[offset + 3] = 255
        } else if stickerMask[pixelIndex] == 1 {
            pixels[offset] = 255
            pixels[offset + 1] = 255
            pixels[offset + 2] = 255
            pixels[offset + 3] = 255
        } else {
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
        }
    }
}

guard
    let outputImage = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fputs("Could not create output image.\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Could not write output image.\n", stderr)
    exit(1)
}

print(outputURL.path)
