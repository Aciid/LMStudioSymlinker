#!/usr/bin/env swift
// Renders the SF Symbol "link" to a 1024×1024 PNG for use as app icon.
// Compile and run: swiftc -framework AppKit -framework Foundation -o render-link-icon render-link-icon.swift && ./render-link-icon <output-path>
// Or run from build-app.sh which compiles and invokes with the iconset path.

import AppKit
import Foundation

let size: CGFloat = 1024
let symbolName = "link"

guard let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
  fputs("error: SF Symbol '\(symbolName)' not found\n", stderr)
  exit(1)
}

let config = NSImage.SymbolConfiguration(pointSize: size * 0.8, weight: .regular)
guard let configured = symbolImage.withSymbolConfiguration(config) else {
  fputs("error: could not configure symbol\n", stderr)
  exit(1)
}

let outputImage = NSImage(size: NSSize(width: size, height: size))
outputImage.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
NSColor.black.set()
configured.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
outputImage.unlockFocus()

guard let tiffData = outputImage.tiffRepresentation,
      let bitmapRep = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
  fputs("error: could not encode PNG\n", stderr)
  exit(1)
}

let outputPath = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let url = URL(fileURLWithPath: outputPath)
do {
  try pngData.write(to: url)
} catch {
  fputs("error: could not write \(outputPath): \(error)\n", stderr)
  exit(1)
}

print("Wrote \(outputPath)")
