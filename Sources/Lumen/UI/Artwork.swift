import AppKit
import ImageIO
import SwiftUI

/// Visuel d'un jeu : PNG, JPEG, WebP ou GIF, animé si le fichier l'est.
/// Remplit son cadre (comme scaledToFill) et repli dégradé + nom si aucun fichier.
struct Artwork: View {
    let url: URL?
    let fallback: String

    var body: some View {
        ZStack {
            if url != nil {
                AnimatedImageLayer(url: url)
            } else {
                LinearGradient(colors: [.indigo, .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(fallback)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding()
                    .opacity(0.7)
            }
        }
        .clipped()
    }
}

/// Affiche une image animée (GIF, WebP animé) avec une animation de contenu Core Animation.
struct AnimatedImageLayer: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> AnimatedImageNSView {
        AnimatedImageNSView()
    }

    func updateNSView(_ view: AnimatedImageNSView, context: Context) {
        view.load(url)
    }
}

final class AnimatedImageNSView: NSView {
    private var loadedURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non utilisé")
    }

    func load(_ url: URL?) {
        guard url != loadedURL else { return }
        loadedURL = url
        layer?.removeAnimation(forKey: "frames")
        layer?.contents = nil

        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
        let count = CGImageSourceGetCount(source)
        if count <= 1 {
            layer?.contents = CGImageSourceCreateImageAtIndex(source, 0, nil)
            return
        }

        var frames: [CGImage] = []
        var delays: [Double] = []
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(frame)
            delays.append(Self.delay(at: index, in: source))
        }
        guard frames.count > 1 else {
            layer?.contents = frames.first
            return
        }

        let total = delays.reduce(0, +)
        var keyTimes: [NSNumber] = []
        var elapsed = 0.0
        for delay in delays {
            keyTimes.append(NSNumber(value: elapsed / total))
            elapsed += delay
        }

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.keyTimes = keyTimes
        animation.duration = total
        animation.calculationMode = .discrete
        animation.repeatCount = .infinity
        layer?.add(animation, forKey: "frames")
    }

    /// Durée d'une image, en secondes, pour GIF ou WebP. Valeur de repli : 0,1 s.
    private static func delay(at index: Int, in source: CGImageSource) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let webp = properties?[kCGImagePropertyWebPDictionary] as? [CFString: Any]
        let value = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? (webp?[kCGImagePropertyWebPUnclampedDelayTime] as? Double)
            ?? (webp?[kCGImagePropertyWebPDelayTime] as? Double)
            ?? 0.1
        return max(value, 0.02)
    }
}
