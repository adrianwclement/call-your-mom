//
//  TamagotchiSpriteCatalog.swift
//  call-your-mom
//

import SwiftUI
import UIKit

struct TamagotchiSpriteProfile: Identifiable, Equatable {
    let id: String
    let displayName: String
    let badgeSymbol: String
    let badgeColor: Color
    let highlightColor: Color
    let highHealthShellColor: Color
    let midHealthShellColor: Color
    let lowHealthShellColor: Color
    let atlas: TamagotchiAtlas?

    static func == (lhs: TamagotchiSpriteProfile, rhs: TamagotchiSpriteProfile) -> Bool {
        lhs.id == rhs.id
    }
}

struct TamagotchiAtlas: Equatable {
    let imageName: String
    let frameSize: CGSize
    let idleAnimation: AtlasIdleAnimation
}

struct AtlasIdleAnimation: Equatable {
    let fps: Double
    let frames: [AtlasFrame]

    var frameInterval: TimeInterval {
        1.0 / max(fps, 1)
    }
}

struct AtlasFrame: Equatable {
    let column: Int
    let row: Int
}

enum TamagotchiSpriteCatalog {
    static let defaultProfiles: [TamagotchiSpriteProfile] = [
        TamagotchiSpriteProfile(
            id: "skyBuddy",
            displayName: "Sky Buddy",
            badgeSymbol: "cloud.fill",
            badgeColor: Color(hex: "#BAEAFF"),
            highlightColor: Color(hex: "#54A6FA"),
            highHealthShellColor: Color(hex: "#73BAFA"),
            midHealthShellColor: Color(hex: "#9BB3EB"),
            lowHealthShellColor: Color(hex: "#BA9ED6"),
            atlas: nil
        ),
        TamagotchiSpriteProfile(
            id: "peachPal",
            displayName: "Peach Pal",
            badgeSymbol: "sparkles",
            badgeColor: Color(hex: "#FFE594"),
            highlightColor: Color(hex: "#FAA15C"),
            highHealthShellColor: Color(hex: "#FAA68A"),
            midHealthShellColor: Color(hex: "#EDB3A1"),
            lowHealthShellColor: Color(hex: "#CF94B8"),
            atlas: nil
        ),
        TamagotchiSpriteProfile(
            id: "mintBean",
            displayName: "Mint Bean",
            badgeSymbol: "leaf.fill",
            badgeColor: Color(hex: "#B8FFDA"),
            highlightColor: Color(hex: "#1FC29A"),
            highHealthShellColor: Color(hex: "#63D1AD"),
            midHealthShellColor: Color(hex: "#8FBFA8"),
            lowHealthShellColor: Color(hex: "#85A0A3"),
            atlas: nil
        )
    ]

    static var defaultSprite: TamagotchiSpriteProfile {
        defaultProfiles.first ?? TamagotchiSpriteProfile(
            id: "default",
            displayName: "Default",
            badgeSymbol: "heart.fill",
            badgeColor: .white,
            highlightColor: .blue,
            highHealthShellColor: .blue,
            midHealthShellColor: .blue.opacity(0.75),
            lowHealthShellColor: .blue.opacity(0.55),
            atlas: nil
        )
    }

    static func load() -> [TamagotchiSpriteProfile] {
        var orderedProfiles = defaultProfiles
        var profileByID = Dictionary(uniqueKeysWithValues: defaultProfiles.map { ($0.id, $0) })

        for subdirectory in [nil, ".atlas", "atlas"] {
            guard
                let registryURL = registryURL(in: subdirectory),
                let registryData = try? Data(contentsOf: registryURL),
                let registry = try? JSONDecoder().decode(AtlasRegistry.self, from: registryData)
            else {
                continue
            }

            for manifestName in registry.manifests {
                guard
                    let manifestURL = manifestURL(named: manifestName, in: subdirectory),
                    let manifestData = try? Data(contentsOf: manifestURL),
                    let manifest = try? JSONDecoder().decode(TamagotchiManifest.self, from: manifestData)
                else {
                    continue
                }

                let sprite = profile(from: manifest)
                if profileByID[sprite.id] == nil {
                    orderedProfiles.append(sprite)
                }
                profileByID[sprite.id] = sprite
            }
            break
        }

        return orderedProfiles.compactMap { profileByID[$0.id] }
    }

    private static func registryURL(in subdirectory: String?) -> URL? {
        if let subdirectory {
            return Bundle.main.url(forResource: "registry", withExtension: "json", subdirectory: subdirectory)
        }
        return Bundle.main.url(forResource: "registry", withExtension: "json")
    }

    private static func manifestURL(named name: String, in subdirectory: String?) -> URL? {
        if let subdirectory {
            return Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
        }
        return Bundle.main.url(forResource: name, withExtension: "json")
    }

    private static func profile(from manifest: TamagotchiManifest) -> TamagotchiSpriteProfile {
        TamagotchiSpriteProfile(
            id: manifest.id,
            displayName: manifest.displayName,
            badgeSymbol: manifest.badgeSymbol,
            badgeColor: Color(hex: manifest.badgeColor),
            highlightColor: Color(hex: manifest.highlightColor),
            highHealthShellColor: Color(hex: manifest.healthShellColors.high),
            midHealthShellColor: Color(hex: manifest.healthShellColors.mid),
            lowHealthShellColor: Color(hex: manifest.healthShellColors.low),
            atlas: atlas(from: manifest.atlas)
        )
    }

    private static func atlas(from atlas: AtlasManifest?) -> TamagotchiAtlas? {
        guard let atlas else { return nil }

        let frames = atlas.idleAnimation.frames.map { AtlasFrame(column: $0.column, row: $0.row) }
        guard !frames.isEmpty else { return nil }

        let idleAnimation = AtlasIdleAnimation(
            fps: max(atlas.idleAnimation.fps, 1),
            frames: frames
        )

        return TamagotchiAtlas(
            imageName: atlas.image,
            frameSize: CGSize(width: atlas.frameSize.width, height: atlas.frameSize.height),
            idleAnimation: idleAnimation
        )
    }
}

enum TamagotchiAtlasRenderer {
    static func frameImage(for atlas: TamagotchiAtlas, frameIndex: Int) -> UIImage? {
        guard !atlas.idleAnimation.frames.isEmpty else { return nil }
        let normalizedIndex = ((frameIndex % atlas.idleAnimation.frames.count) + atlas.idleAnimation.frames.count) % atlas.idleAnimation.frames.count
        let frame = atlas.idleAnimation.frames[normalizedIndex]
        let cacheKey = "\(atlas.imageName)#\(frame.column)x\(frame.row)#\(Int(atlas.frameSize.width))x\(Int(atlas.frameSize.height))" as NSString

        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard
            let sheetImage = UIImage(named: atlas.imageName),
            let cgImage = sheetImage.cgImage
        else {
            return nil
        }

        let scale = sheetImage.scale
        let cropRect = CGRect(
            x: CGFloat(frame.column) * atlas.frameSize.width * scale,
            y: CGFloat(frame.row) * atlas.frameSize.height * scale,
            width: atlas.frameSize.width * scale,
            height: atlas.frameSize.height * scale
        ).integral

        guard let frameCGImage = cgImage.cropping(to: cropRect) else { return nil }
        let frameImage = UIImage(cgImage: frameCGImage, scale: scale, orientation: .up)
        cache.setObject(frameImage, forKey: cacheKey)
        return frameImage
    }

    private static let cache = NSCache<NSString, UIImage>()
}

private struct AtlasRegistry: Decodable {
    let manifests: [String]
}

private struct TamagotchiManifest: Decodable {
    let id: String
    let displayName: String
    let badgeSymbol: String
    let badgeColor: String
    let highlightColor: String
    let healthShellColors: HealthShellColors
    let atlas: AtlasManifest?
}

private struct HealthShellColors: Decodable {
    let high: String
    let mid: String
    let low: String
}

private struct AtlasManifest: Decodable {
    let image: String
    let frameSize: AtlasSize
    let idleAnimation: IdleAnimationManifest
}

private struct AtlasSize: Decodable {
    let width: Double
    let height: Double
}

private struct AtlasCell: Decodable {
    let column: Int
    let row: Int
}

private struct IdleAnimationManifest: Decodable {
    let fps: Double
    let frames: [AtlasCell]
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        switch sanitized.count {
        case 8:
            red = (value & 0xFF000000) >> 24
            green = (value & 0x00FF0000) >> 16
            blue = (value & 0x0000FF00) >> 8
            alpha = value & 0x000000FF
        default:
            red = (value & 0xFF0000) >> 16
            green = (value & 0x00FF00) >> 8
            blue = value & 0x0000FF
            alpha = 0xFF
        }

        self.init(
            .sRGB,
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: Double(alpha) / 255.0
        )
    }
}
