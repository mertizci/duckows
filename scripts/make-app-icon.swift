#!/usr/bin/env swift
//
// Generates the Duckows app icon at every size the asset catalog needs.
//
// The icon is drawn rather than hand-authored so it can be tweaked in one place
// and regenerated: an amber squircle, a duck silhouette, and a taskbar strip
// along the bottom edge that reads as the product even at 16pt.
//
// Usage:
//   swift scripts/make-app-icon.swift [output-directory]
//
// Defaults to Duckows/Assets.xcassets/AppIcon.appiconset next to the repo root.

import AppKit
import CoreGraphics
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]

let outputDirectory: URL = {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1])
    }
    let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    return scriptDir
        .deletingLastPathComponent()
        .appendingPathComponent("Duckows/Assets.xcassets/AppIcon.appiconset")
}()

// MARK: - Colors

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let amberTop = rgb(255, 205, 66)
let amberBottom = rgb(240, 148, 12)
let beakOrange = rgb(238, 108, 24)
let inkColor = rgb(58, 38, 8)
let duckWhite = rgb(255, 253, 246)

// MARK: - Shapes

/// A continuous-corner rounded rectangle close to Apple's squircle.
func squirclePath(in rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let r = min(radius, min(rect.width, rect.height) / 2)
    // Pulling the control points to ~0.44 of the radius approximates the
    // superellipse macOS uses; plain arcs read visibly "rounder".
    let c = r * 0.44

    path.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
    path.addCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                  control1: CGPoint(x: rect.minX, y: rect.minY + c),
                  control2: CGPoint(x: rect.minX + c, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                  control1: CGPoint(x: rect.maxX - c, y: rect.minY),
                  control2: CGPoint(x: rect.maxX, y: rect.minY + c))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    path.addCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                  control1: CGPoint(x: rect.maxX, y: rect.maxY - c),
                  control2: CGPoint(x: rect.maxX - c, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                  control1: CGPoint(x: rect.minX + c, y: rect.maxY),
                  control2: CGPoint(x: rect.minX, y: rect.maxY - c))
    path.closeSubpath()
    return path
}

/// Draws the icon into `context`, which is assumed to be `side` x `side`
/// points with a bottom-left origin.
func drawIcon(in ctx: CGContext, side: CGFloat) {
    let inset = side * 0.094
    let plate = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let plateRadius = plate.width * 0.2237

    // Background plate with a vertical amber gradient.
    ctx.saveGState()
    ctx.addPath(squirclePath(in: plate, radius: plateRadius))
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [amberTop, amberBottom] as CFArray,
                                 locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: plate.midX, y: plate.maxY),
                               end: CGPoint(x: plate.midX, y: plate.minY),
                               options: [])
    }
    ctx.restoreGState()

    // The taskbar strip: the product idea, sitting where the bar sits on screen.
    let barHeight = plate.height * 0.17
    let barRect = CGRect(x: plate.minX, y: plate.minY, width: plate.width, height: barHeight)
    ctx.saveGState()
    ctx.addPath(squirclePath(in: plate, radius: plateRadius))
    ctx.clip()
    ctx.setFillColor(inkColor.copy(alpha: 0.28) ?? inkColor)
    ctx.fill(barRect)
    ctx.restoreGState()

    // Three taskbar buttons. Below 32pt they turn to mud, so they are dropped.
    if side >= 32 {
        let tile = barHeight * 0.46
        let gap = tile * 0.55
        let totalWidth = tile * 3 + gap * 2
        var x = plate.midX - totalWidth / 2
        let y = barRect.midY - tile / 2
        for index in 0..<3 {
            let alpha: CGFloat = index == 0 ? 0.95 : 0.55
            ctx.setFillColor(duckWhite.copy(alpha: alpha) ?? duckWhite)
            ctx.addPath(squirclePath(in: CGRect(x: x, y: y, width: tile, height: tile),
                                     radius: tile * 0.3))
            ctx.fillPath()
            x += tile + gap
        }
    }

    // Duck: body, head, beak, eye. Proportions are tuned so the silhouette still
    // reads at 16pt, where every detail below collapses into the body shape.
    let bodyWidth = plate.width * 0.62
    let bodyHeight = plate.height * 0.40
    let bodyRect = CGRect(x: plate.midX - bodyWidth * 0.46,
                          y: plate.minY + barHeight + plate.height * 0.055,
                          width: bodyWidth,
                          height: bodyHeight)
    ctx.setFillColor(duckWhite)
    ctx.fillEllipse(in: bodyRect)

    let headSize = plate.width * 0.34
    let headRect = CGRect(x: plate.midX - headSize * 0.05,
                          y: bodyRect.maxY - headSize * 0.28,
                          width: headSize,
                          height: headSize)
    ctx.setFillColor(duckWhite)
    ctx.fillEllipse(in: headRect)

    // Beak
    let beak = CGMutablePath()
    let beakX = headRect.maxX - headSize * 0.06
    let beakY = headRect.midY + headSize * 0.02
    let beakLength = headSize * 0.46
    let beakThickness = headSize * 0.22
    beak.move(to: CGPoint(x: beakX, y: beakY + beakThickness / 2))
    beak.addLine(to: CGPoint(x: beakX + beakLength, y: beakY + beakThickness * 0.15))
    beak.addLine(to: CGPoint(x: beakX + beakLength, y: beakY - beakThickness * 0.35))
    beak.addLine(to: CGPoint(x: beakX, y: beakY - beakThickness / 2))
    beak.closeSubpath()
    ctx.setFillColor(beakOrange)
    ctx.addPath(beak)
    ctx.fillPath()

    if side >= 64 {
        let eyeSize = headSize * 0.15
        ctx.setFillColor(inkColor)
        ctx.fillEllipse(in: CGRect(x: headRect.midX + headSize * 0.06,
                                   y: headRect.midY + headSize * 0.12,
                                   width: eyeSize,
                                   height: eyeSize))
    }
}

// MARK: - Rendering

func render(side: Int) throws -> Data {
    guard let ctx = CGContext(data: nil,
                              width: side,
                              height: side,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "make-app-icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Could not create a \(side)pt context"])
    }

    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, side: CGFloat(side))

    guard let image = ctx.makeImage() else {
        throw NSError(domain: "make-app-icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Could not snapshot the \(side)pt context"])
    }

    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: side, height: side)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-app-icon", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Could not encode the \(side)pt PNG"])
    }
    return data
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for side in sizes {
    let data = try render(side: side)
    let url = outputDirectory.appendingPathComponent("AppIcon-\(side).png")
    try data.write(to: url)
    print("wrote \(url.lastPathComponent) (\(data.count) bytes)")
}

print("Icons written to \(outputDirectory.path)")
