import SwiftUI

struct CelestialBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    private var usesLargeCanvas: Bool { horizontalSizeClass == .regular }
    private var shouldAnimate: Bool {
        !reduceMotion && scenePhase == .active
    }
    private var refreshInterval: TimeInterval {
        // The iPad canvas covers far more pixels. Twelve quiet updates per
        // second are enough for the slow nebula drift without competing with
        // scrolling; compact screens keep the smoother 24 fps treatment.
        usesLargeCanvas ? 1.0 / 12.0 : 1.0 / 24.0
    }

    var body: some View {
        Group {
            if shouldAnimate {
                TimelineView(.periodic(from: .now, by: refreshInterval)) { timeline in
                    backdrop(time: timeline.date.timeIntervalSinceReferenceDate, animates: true)
                }
            } else {
                // Reduce Motion and inactive scenes use a still sky.
                backdrop(time: 0, animates: false)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func backdrop(time: TimeInterval, animates: Bool) -> some View {
        GeometryReader { proxy in
            ZStack {
                    LinearGradient(
                        stops: [
                            .init(color: Color.celestialNight, location: 0),
                            .init(color: Color.celestialIndigo, location: 0.54),
                            .init(color: Color.celestialPlum, location: 1),
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )

                    RadialGradient(
                        colors: [Color.celestialLavender.opacity(0.30), .clear],
                        center: UnitPoint(
                            x: 0.18 + 0.018 * sin(time * 0.035),
                            y: 0.12 + 0.012 * cos(time * 0.030)
                        ),
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.60
                    )

                    RadialGradient(
                        colors: [Color.celestialPink.opacity(0.17), .clear],
                        center: UnitPoint(
                            x: 0.82 + 0.014 * cos(time * 0.028),
                            y: 0.72 + 0.018 * sin(time * 0.024)
                        ),
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.52
                    )

                    LinearGradient(
                        colors: [.clear, Color.celestialLavender.opacity(0.08), .clear],
                        startPoint: UnitPoint(x: 0.06, y: 0.82),
                        endPoint: UnitPoint(x: 0.94, y: 0.18)
                    )
                    .blendMode(.screen)
                    .rotationEffect(.degrees(-7 + sin(time * 0.018) * 1.5))
                    .scaleEffect(1.22)

                    PremiumStarField(
                        time: time,
                        reduceMotion: !animates,
                        starCount: usesLargeCanvas ? 36 : 72
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct PremiumStarField: View {
    let time: TimeInterval
    let reduceMotion: Bool
    let starCount: Int

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            drawConstellations(in: &context, size: size)

            for index in 0..<starCount {
                let depth = CGFloat(index % 3) / 2
                let baseX = unit(index * 53 + 17)
                let baseY = unit(index * 79 + 31)
                let drift = reduceMotion ? 0 : CGFloat(time.truncatingRemainder(dividingBy: 180)) * (0.000018 + depth * 0.000022)
                let xUnit = (baseX + drift).truncatingRemainder(dividingBy: 1)
                let yDrift = reduceMotion ? 0 : sin(time * (0.030 + Double(index % 5) * 0.004) + Double(index)) * Double(1.2 + depth)
                let point = CGPoint(
                    x: xUnit * size.width,
                    y: baseY * size.height + yDrift
                )

                let pulse = reduceMotion
                    ? 0.72
                    : 0.66 + 0.34 * sin(time * (0.42 + Double(index % 7) * 0.055) + Double(index) * 1.73)
                let opacity = max(0.18, pulse) * Double(0.34 + depth * 0.48)
                let radius = 0.45 + depth * 1.05 + CGFloat(index % 11 == 0 ? 0.7 : 0)
                let tint: Color = index % 13 == 0
                    ? .celestialGold
                    : (index % 9 == 0 ? .celestialLavender : .white)

                if index % 11 == 0 {
                    let haloRadius = radius * 3.1
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: point.x - haloRadius,
                            y: point.y - haloRadius,
                            width: haloRadius * 2,
                            height: haloRadius * 2
                        )),
                        with: .color(tint.opacity(opacity * 0.12))
                    )
                }

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .color(tint.opacity(opacity))
                )

                if index % 23 == 0 {
                    var glint = Path()
                    glint.move(to: CGPoint(x: point.x - radius * 3.2, y: point.y))
                    glint.addLine(to: CGPoint(x: point.x + radius * 3.2, y: point.y))
                    glint.move(to: CGPoint(x: point.x, y: point.y - radius * 3.2))
                    glint.addLine(to: CGPoint(x: point.x, y: point.y + radius * 3.2))
                    context.stroke(glint, with: .color(tint.opacity(opacity * 0.55)), lineWidth: 0.55)
                }
            }
        }
    }

    private func drawConstellations(in context: inout GraphicsContext, size: CGSize) {
        let groups: [[CGPoint]] = [
            [CGPoint(x: 0.64, y: 0.13), CGPoint(x: 0.70, y: 0.10), CGPoint(x: 0.76, y: 0.16), CGPoint(x: 0.72, y: 0.22)],
            [CGPoint(x: 0.10, y: 0.48), CGPoint(x: 0.16, y: 0.43), CGPoint(x: 0.22, y: 0.46)],
        ]

        for group in groups {
            var path = Path()
            for (index, point) in group.enumerated() {
                let resolved = CGPoint(x: point.x * size.width, y: point.y * size.height)
                if index == 0 { path.move(to: resolved) } else { path.addLine(to: resolved) }
            }
            context.stroke(path, with: .color(Color.celestialLavender.opacity(0.10)), lineWidth: 0.7)
        }
    }

    private func unit(_ seed: Int) -> CGFloat {
        CGFloat((seed &* 37 &+ 19) % 997) / 997
    }
}

struct CelestialCardBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.celestialIndigo, Color.celestialPlum],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                for index in 0..<22 {
                    let x = CGFloat((index * 41 + 7) % 97) / 96 * size.width
                    let y = CGFloat((index * 67 + 19) % 89) / 88 * size.height
                    let radius = CGFloat(index % 4 == 0 ? 1.6 : 0.8)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                        with: .color((index % 6 == 0 ? Color.celestialGold : .white).opacity(0.72))
                    )
                }
            }
        }
    }
}

private struct CelestialSurfaceModifier<SurfaceShape: Shape, BaseStyle: ShapeStyle, ReducedStyle: ShapeStyle>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let baseStyle: BaseStyle
    let reducedStyle: ReducedStyle
    let shape: SurfaceShape
    let reducedBoundaryColor: Color

    func body(content: Content) -> some View {
        content.background {
            shape
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(reducedStyle)
                        : AnyShapeStyle(baseStyle)
                )
                .overlay {
                    if reduceTransparency {
                        shape.stroke(reducedBoundaryColor, lineWidth: 1)
                    }
                }
        }
    }
}

private struct CelestialGlassButtonStyleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isProminent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            if isProminent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        } else if isProminent {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

extension View {
    /// Keeps celestial panels visually separated when Reduce Transparency is on.
    func celestialSurface<SurfaceShape: Shape, BaseStyle: ShapeStyle>(
        _ baseStyle: BaseStyle,
        in shape: SurfaceShape,
        reducedColor: Color = .celestialSurfaceOpaque,
        reducedBoundaryColor: Color = .white.opacity(0.30)
    ) -> some View {
        modifier(CelestialSurfaceModifier(
            baseStyle: baseStyle,
            reducedStyle: reducedColor,
            shape: shape,
            reducedBoundaryColor: reducedBoundaryColor
        ))
    }

    /// Variant for panels whose accessible fallback is a gradient or other style.
    func celestialSurface<SurfaceShape: Shape, BaseStyle: ShapeStyle, ReducedStyle: ShapeStyle>(
        _ baseStyle: BaseStyle,
        reducedStyle: ReducedStyle,
        in shape: SurfaceShape,
        reducedBoundaryColor: Color = .white.opacity(0.30)
    ) -> some View {
        modifier(CelestialSurfaceModifier(
            baseStyle: baseStyle,
            reducedStyle: reducedStyle,
            shape: shape,
            reducedBoundaryColor: reducedBoundaryColor
        ))
    }

    /// Liquid Glass is replaced by a bordered system control when transparency
    /// is reduced, preserving the action and selected state without blur.
    func celestialGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(CelestialGlassButtonStyleModifier(isProminent: prominent))
    }
}

extension Color {
    static let celestialNight = Color(red: 0.045, green: 0.055, blue: 0.20)
    static let celestialIndigo = Color(red: 0.16, green: 0.13, blue: 0.37)
    static let celestialPlum = Color(red: 0.34, green: 0.20, blue: 0.43)
    static let celestialLavender = Color(red: 0.72, green: 0.62, blue: 0.90)
    static let celestialPink = Color(red: 0.96, green: 0.60, blue: 0.76)
    static let celestialGold = Color(red: 1.00, green: 0.84, blue: 0.47)
    static let celestialSurfaceOpaque = Color(red: 0.12, green: 0.10, blue: 0.27)
    static let celestialSurfaceElevated = Color(red: 0.19, green: 0.14, blue: 0.34)
}
