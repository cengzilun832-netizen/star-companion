import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 || CommandLine.arguments.count == 6 else {
    fputs("Usage: make_lucky_star_gif.swift input.png output.gif [bounce|cry|shake|sigh] [column row]\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let motion = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : "bounce"

guard
    let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let loadedImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.gif.identifier as CFString,
        12,
        nil
    )
else {
    fputs("Could not open input image or create GIF destination.\n", stderr)
    exit(1)
}

let sourceImage: CGImage
if CommandLine.arguments.count == 6,
   let column = Int(CommandLine.arguments[4]),
   let row = Int(CommandLine.arguments[5]),
   (0..<3).contains(column),
   (0..<2).contains(row) {
    let cellWidth = loadedImage.width / 3
    let cellHeight = loadedImage.height / 2
    let cropRect = CGRect(
        x: column * cellWidth,
        y: row * cellHeight,
        width: cellWidth,
        height: cellHeight
    )
    guard let croppedImage = loadedImage.cropping(to: cropRect) else {
        fputs("Could not crop sticker sheet cell.\n", stderr)
        exit(1)
    }
    sourceImage = croppedImage
} else {
    sourceImage = loadedImage
}

let canvasSize = 512
let loopProperties: [CFString: Any] = [
    kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0
    ]
]
CGImageDestinationSetProperties(destination, loopProperties as CFDictionary)

let xOffsets: [CGFloat]
let yOffsets: [CGFloat]
let scales: [CGFloat]

switch motion {
case "cry":
    xOffsets = [0, -1, 0, 1, 0, -1, 0, 1, 0, -1, 0, 1]
    yOffsets = [2, 0, -2, -4, -2, 0, 2, 0, -2, -4, -2, 0]
    scales = [0.95, 0.95, 0.94, 0.94, 0.94, 0.95, 0.95, 0.95, 0.94, 0.94, 0.94, 0.95]
case "shake":
    xOffsets = [-7, 7, -6, 6, -5, 5, -4, 4, -3, 3, -2, 2]
    yOffsets = Array(repeating: 0, count: 12)
    scales = Array(repeating: 0.94, count: 12)
case "sigh":
    xOffsets = Array(repeating: 0, count: 12)
    yOffsets = [5, 3, 1, -2, -5, -8, -10, -8, -5, -2, 1, 3]
    scales = [0.95, 0.95, 0.94, 0.94, 0.93, 0.92, 0.92, 0.92, 0.93, 0.94, 0.94, 0.95]
default:
    xOffsets = Array(repeating: 0, count: 12)
    yOffsets = [10, 5, -5, -14, -20, -14, -5, 5, 10, 12, 12, 10]
    scales = [0.92, 0.95, 0.98, 1.02, 1.05, 1.02, 0.98, 0.95, 0.92, 0.91, 0.91, 0.92]
}

for index in yOffsets.indices {
    guard let context = CGContext(
        data: nil,
        width: canvasSize,
        height: canvasSize,
        bitsPerComponent: 8,
        bytesPerRow: canvasSize * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("Could not create animation frame.\n", stderr)
        exit(1)
    }

    context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
    context.interpolationQuality = .none

    let frameScale = scales[index]
    let side = CGFloat(canvasSize) * frameScale
    let x = (CGFloat(canvasSize) - side) / 2 + xOffsets[index]
    let y = (CGFloat(canvasSize) - side) / 2 + yOffsets[index]
    context.draw(sourceImage, in: CGRect(x: x, y: y, width: side, height: side))

    guard let frame = context.makeImage() else {
        fputs("Could not render animation frame.\n", stderr)
        exit(1)
    }

    let frameProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: 0.08,
            kCGImagePropertyGIFUnclampedDelayTime: 0.08
        ]
    ]
    CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("Could not finish GIF.\n", stderr)
    exit(1)
}

print(outputURL.path)
