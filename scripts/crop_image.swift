import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 7,
      let x = Int(CommandLine.arguments[3]),
      let y = Int(CommandLine.arguments[4]),
      let width = Int(CommandLine.arguments[5]),
      let height = Int(CommandLine.arguments[6]) else {
    fputs("Usage: crop_image.swift input.png output.png x y width height\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let cropped = image.cropping(to: CGRect(x: x, y: y, width: width, height: height)),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fputs("Could not crop image.\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, cropped, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Could not write cropped image.\n", stderr)
    exit(1)
}

print(outputURL.path)
