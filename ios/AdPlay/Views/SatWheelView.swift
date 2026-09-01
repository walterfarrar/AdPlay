import SwiftUI

/// Sat wheel chrome. Plate / fill / combo / hub are separate Equatable canvases
/// so combo meter ticks do not redraw the shadowed plate.
struct SatWheelView: View, Equatable {
    let fraction: Double
    var flash: Bool = false
    var comboFractions: [Double] = [0, 0, 0]
    var comboTracks: [Bool] = [true, false, false]
    var comboSpins: [Double] = [0, 0, 0]
    var comboMultiplier: Double = 1
    var comboTapAt: Date? = nil
    var look: ThemeLook = .ember
    var stage: MinerStage = .level1

    static func == (lhs: SatWheelView, rhs: SatWheelView) -> Bool {
        lhs.fraction == rhs.fraction
            && lhs.flash == rhs.flash
            && lhs.comboFractions == rhs.comboFractions
            && lhs.comboTracks == rhs.comboTracks
            && lhs.comboSpins == rhs.comboSpins
            && lhs.comboMultiplier == rhs.comboMultiplier
            && lhs.comboTapAt == rhs.comboTapAt
            && lhs.look.id == rhs.look.id
            && lhs.stage == rhs.stage
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                SatWheelPlateLayer(look: look, stage: stage)
                    .equatable()
                SatWheelFillLayer(
                    fraction: fraction,
                    flash: flash,
                    comboFractions: comboFractions,
                    comboTracks: comboTracks,
                    look: look,
                    stage: stage
                )
                .equatable()
                SatWheelComboLayer(
                    comboFractions: comboFractions,
                    comboTracks: comboTracks,
                    comboSpins: comboSpins,
                    look: look,
                    stage: stage
                )
                .equatable()
                SatWheelHubLayer(
                    flash: flash,
                    look: look,
                    stage: stage
                )
                .equatable()
                SatWheelComboBadgeLayer(
                    size: size,
                    comboMultiplier: comboMultiplier,
                    look: look
                )
                .equatable()
                .modifier(ComboBadgeShake(
                    shake: ComboEngine.shake(comboMultiplier),
                    tapAt: comboTapAt
                ))
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SatWheelPlateLayer: View, Equatable {
    var look: ThemeLook
    var stage: MinerStage

    static func == (lhs: SatWheelPlateLayer, rhs: SatWheelPlateLayer) -> Bool {
        lhs.look.id == rhs.look.id && lhs.stage == rhs.stage
    }

    var body: some View {
        Canvas { context, canvasSize in
            let size = min(canvasSize.width, canvasSize.height)
            drawWheelPlate(into: &context, canvasSize: canvasSize, size: size, look: look, stage: stage)
        }
    }
}

private struct SatWheelFillLayer: View, Equatable {
    var fraction: Double
    var flash: Bool
    var comboFractions: [Double]
    var comboTracks: [Bool]
    var look: ThemeLook
    var stage: MinerStage

    static func == (lhs: SatWheelFillLayer, rhs: SatWheelFillLayer) -> Bool {
        lhs.fraction == rhs.fraction
            && lhs.flash == rhs.flash
            && lhs.comboFractions == rhs.comboFractions
            && lhs.comboTracks == rhs.comboTracks
            && lhs.look.id == rhs.look.id
            && lhs.stage == rhs.stage
    }

    var body: some View {
        Canvas { context, canvasSize in
            let size = min(canvasSize.width, canvasSize.height)
            drawWheelFill(
                into: &context,
                canvasSize: canvasSize,
                size: size,
                fraction: fraction,
                flash: flash,
                comboFractions: comboFractions,
                comboTracks: comboTracks,
                look: look,
                stage: stage
            )
        }
    }
}

private struct SatWheelComboLayer: View, Equatable {
    var comboFractions: [Double]
    var comboTracks: [Bool]
    var comboSpins: [Double]
    var look: ThemeLook
    var stage: MinerStage

    static func == (lhs: SatWheelComboLayer, rhs: SatWheelComboLayer) -> Bool {
        lhs.comboFractions == rhs.comboFractions
            && lhs.comboTracks == rhs.comboTracks
            && lhs.comboSpins == rhs.comboSpins
            && lhs.look.id == rhs.look.id
            && lhs.stage == rhs.stage
    }

    var body: some View {
        Canvas { context, canvasSize in
            let size = min(canvasSize.width, canvasSize.height)
            drawWheelCombo(
                into: &context,
                canvasSize: canvasSize,
                size: size,
                comboFractions: comboFractions,
                comboTracks: comboTracks,
                comboSpins: comboSpins,
                look: look,
                stage: stage
            )
        }
    }
}

private struct SatWheelHubLayer: View, Equatable {
    var flash: Bool
    var look: ThemeLook
    var stage: MinerStage

    static func == (lhs: SatWheelHubLayer, rhs: SatWheelHubLayer) -> Bool {
        lhs.flash == rhs.flash
            && lhs.look.id == rhs.look.id
            && lhs.stage == rhs.stage
    }

    var body: some View {
        Canvas { context, canvasSize in
            let size = min(canvasSize.width, canvasSize.height)
            drawWheelHub(
                into: &context,
                canvasSize: canvasSize,
                size: size,
                flash: flash,
                look: look,
                stage: stage
            )
        }
    }
}

private struct SatWheelComboBadgeLayer: View, Equatable {
    var size: CGFloat
    var comboMultiplier: Double
    var look: ThemeLook

    static func == (lhs: SatWheelComboBadgeLayer, rhs: SatWheelComboBadgeLayer) -> Bool {
        lhs.size == rhs.size
            && lhs.comboMultiplier == rhs.comboMultiplier
            && lhs.look.id == rhs.look.id
    }

    var body: some View {
        let label = ComboEngine.formatMultiplier(comboMultiplier)
        if !label.isEmpty {
            let heat = ComboEngine.heat(comboMultiplier)
            let fill = look.comboFill(ComboEngine.heatRing(heat))
            let fontSize = size * (0.12 + heat * 0.07)
            Text(label)
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundStyle(fill)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .shadow(color: Color.black.opacity(0.9), radius: 0, x: 0.8, y: 0.8)
                .shadow(color: Color.black.opacity(0.9), radius: 0, x: -0.8, y: 0.8)
                .shadow(color: Color.black.opacity(0.9), radius: 0, x: 0.8, y: -0.8)
                .shadow(color: Color.black.opacity(0.9), radius: 0, x: -0.8, y: -0.8)
                .shadow(color: Color.black.opacity(0.55), radius: 1.4)
                .scaleEffect(1 + heat * 0.1)
                .animation(.spring(response: 0.32, dampingFraction: 0.56), value: label)
                .frame(width: size * 0.46, height: size * 0.3)
        }
    }
}

/// One random hop per tap while heat is high; holds until the next tap.
private struct ComboBadgeShake: ViewModifier {
    var shake: Double
    var tapAt: Date?
    @State private var ox: CGFloat = 0
    @State private var oy: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: ox, y: oy)
            .onChange(of: tapAt) { _, _ in hop() }
            .onChange(of: shake) { _, value in
                if value <= 0.001 {
                    ox = 0
                    oy = 0
                }
            }
    }

    private func hop() {
        let amp = ComboEngine.shakeAmplitude(shake)
        guard amp > 0 else {
            ox = 0
            oy = 0
            return
        }
        ox = CGFloat(Int.random(in: -amp ... amp))
        oy = CGFloat(Int.random(in: -amp ... amp))
    }
}

private struct WheelGeom {
    let center: CGPoint
    let size: CGFloat
    let rim: CGFloat
    let radius: CGFloat
    let comboRim: CGFloat
    let pads: [CGFloat]
    let shown: [Bool]
    let pegOrbit: CGFloat
    let faceR: CGFloat
    let chrome: WheelChrome

    init(canvasSize: CGSize, size: CGFloat, comboFractions: [Double], comboTracks: [Bool], stage: MinerStage) {
        center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        self.size = size
        rim = size * 0.06
        radius = size / 2 - rim / 2
        comboRim = rim * 0.50
        let comboPitch = comboRim * 1.35
        pads = [rim * 1.15, rim * 1.15 + comboPitch, rim * 1.15 + comboPitch * 2]
        let fracs = [
            comboFractions.count > 0 ? comboFractions[0] : 0,
            comboFractions.count > 1 ? comboFractions[1] : 0,
            comboFractions.count > 2 ? comboFractions[2] : 0,
        ]
        shown = [
            (comboTracks.count > 0 ? comboTracks[0] : true) || fracs[0] > 0.001,
            (comboTracks.count > 1 ? comboTracks[1] : false) || fracs[1] > 0.001,
            (comboTracks.count > 2 ? comboTracks[2] : false) || fracs[2] > 0.001,
        ]
        let innerIdx = shown[2] ? 2 : (shown[1] ? 1 : 0)
        let innerRadius = size / 2 - pads[innerIdx]
        pegOrbit = max(size * 0.16, innerRadius - comboRim * 0.55 - 5)
        faceR = size * 0.48 - rim * 0.85
        chrome = stage.wheelChrome
    }
}

private func drawWheelPlate(
    into context: inout GraphicsContext,
    canvasSize: CGSize,
    size: CGFloat,
    look: ThemeLook,
    stage: MinerStage
) {
    let g = WheelGeom(canvasSize: canvasSize, size: size, comboFractions: [0, 0, 0], comboTracks: [true, false, false], stage: stage)
    let chrome = g.chrome
    let center = g.center
    let rim = g.rim
    let radius = g.radius
    let ink = Color("BrandInk")
    let gold = Color(red: 0.95, green: 0.78, blue: 0.28)
    let teal = Color(red: 0.20, green: 0.92, blue: 0.85)

    if chrome.halo > 0.001 {
        fillCircle(
            &context,
            center: center,
            radius: size * 0.52,
            color: (chrome.tealMix > 0.35 ? teal : look.accent).opacity(chrome.halo * 0.55)
        )
        fillCircle(
            &context,
            center: center,
            radius: size * 0.48,
            color: Color.black.opacity(0.35)
        )
    }

    let plateR = radius + rim * 0.5
    var plateCtx = context
    plateCtx.addFilter(.shadow(color: .black.opacity(0.55), radius: 10))
    plateCtx.fill(
        Path(ellipseIn: CGRect(x: center.x - plateR, y: center.y - plateR, width: plateR * 2, height: plateR * 2)),
        with: .radialGradient(
            Gradient(colors: [
                Color(
                    red: 0.10 + 0.06 * chrome.tealMix,
                    green: 0.11 + 0.14 * chrome.tealMix,
                    blue: 0.17 + 0.05 * chrome.tealMix
                ),
                Color(red: 0.03, green: 0.035, blue: 0.055),
            ]),
            center: center,
            startRadius: 0,
            endRadius: plateR
        )
    )

    if chrome.goldRim > 0.001 {
        context.stroke(
            Path(ellipseIn: CGRect(
                x: center.x - radius - rim * 0.35,
                y: center.y - radius - rim * 0.35,
                width: (radius + rim * 0.35) * 2,
                height: (radius + rim * 0.35) * 2
            )),
            with: .color(gold.opacity(chrome.goldRim)),
            lineWidth: 2.2
        )
    }

    if chrome.bevel > 0.001 {
        let bevelR = g.faceR - 2
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - bevelR, y: center.y - bevelR, width: bevelR * 2, height: bevelR * 2)),
            with: .color(ink.opacity(chrome.bevel)),
            lineWidth: 1.4
        )
    }
}

private func drawWheelFill(
    into context: inout GraphicsContext,
    canvasSize: CGSize,
    size: CGFloat,
    fraction: Double,
    flash: Bool,
    comboFractions: [Double],
    comboTracks: [Bool],
    look: ThemeLook,
    stage: MinerStage
) {
    let g = WheelGeom(
        canvasSize: canvasSize,
        size: size,
        comboFractions: comboFractions,
        comboTracks: comboTracks,
        stage: stage
    )
    let chrome = g.chrome
    let center = g.center
    let rim = g.rim
    let radius = g.radius
    let ink = Color("BrandInk")
    let gold = Color(red: 0.95, green: 0.78, blue: 0.28)
    let frac = min(1, max(0, fraction))

    if frac > 0.0005 {
        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + frac * 360),
            clockwise: false
        )
        if chrome.fillBloom > 0.001 || flash {
            var glow = context
            glow.addFilter(.shadow(
                color: (flash ? look.accent : look.fill).opacity(0.55 + chrome.fillBloom * 0.45),
                radius: 10 + chrome.fillBloom * 10
            ))
            glow.stroke(
                arc,
                with: .color(flash ? look.accent : look.fill),
                style: StrokeStyle(lineWidth: rim, lineCap: .round)
            )
        }
        if flash {
            var glow = context
            glow.addFilter(.shadow(color: look.accent.opacity(0.9), radius: 16))
            glow.stroke(
                arc,
                with: .color(look.accent),
                style: StrokeStyle(lineWidth: rim, lineCap: .round)
            )
        } else {
            context.stroke(
                arc,
                with: .linearGradient(
                    Gradient(colors: [look.fill, look.fillHot, look.fill]),
                    startPoint: CGPoint(x: center.x, y: center.y - radius),
                    endPoint: CGPoint(x: center.x, y: center.y + radius)
                ),
                style: StrokeStyle(lineWidth: rim, lineCap: .round)
            )
        }
    }

    let spin = frac * 360
    let faceR = g.faceR
    let clipR = g.radius - g.rim * 0.5
    let clipRect = CGRect(x: center.x - clipR, y: center.y - clipR, width: clipR * 2, height: clipR * 2)
    context.drawLayer { layer in
        layer.clip(to: Path(ellipseIn: clipRect))
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .degrees(spin))
        let dest = CGRect(x: -clipR, y: -clipR, width: clipR * 2, height: clipR * 2)
        layer.draw(Image(stage.wheelFaceName), in: dest)
        layer.fill(Path(ellipseIn: dest), with: .color(.black.opacity(0.36)))
    }

    if chrome.gearTeeth > 0 {
        var gears = Path()
        appendTicks(
            &gears,
            center: center,
            count: chrome.gearTeeth,
            startDeg: spin - 90,
            stepDeg: 360 / Double(chrome.gearTeeth),
            outer: faceR - 1,
            length: rim * 0.42
        )
        context.stroke(
            gears,
            with: .color((chrome.goldRim > 0.4 ? gold : ink).opacity(0.40 + chrome.goldRim * 0.25)),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
        )
    }

    let tick = Color(red: 244 / 255, green: 245 / 255, blue: 250 / 255)
    var faceMinor = Path()
    appendTicks(&faceMinor, center: center, count: 60, startDeg: spin - 90, stepDeg: 6, outer: size * 0.365, length: 7)
    context.stroke(
        faceMinor,
        with: .color(tick.opacity(min(1, chrome.tickMinor + 0.38))),
        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
    )
    var faceMajor = Path()
    appendTicks(&faceMajor, center: center, count: 12, startDeg: spin - 90, stepDeg: 30, outer: size * 0.38, length: 11)
    context.stroke(
        faceMajor,
        with: .color(tick.opacity(min(1, chrome.tickMajor + 0.22))),
        style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
    )
    var faceCardinal = Path()
    appendTicks(&faceCardinal, center: center, count: 4, startDeg: spin - 90, stepDeg: 90, outer: size * 0.38, length: 16)
    context.stroke(
        faceCardinal,
        with: .color(tick.opacity(min(1, chrome.tickCardinal + 0.08))),
        style: StrokeStyle(lineWidth: 3.2, lineCap: .round)
    )

    let pegAngle = (frac * 360 - 90) * .pi / 180
    let peg = CGPoint(
        x: center.x + cos(pegAngle) * g.pegOrbit,
        y: center.y + sin(pegAngle) * g.pegOrbit
    )
    fillCircle(&context, center: peg, radius: 5, color: ink.opacity(0.75))
    fillCircle(&context, center: peg, radius: 3.5, color: look.accent.opacity(0.98))

    if flash {
        context.stroke(
            Path(ellipseIn: CGRect(
                x: center.x - size / 2 + 1,
                y: center.y - size / 2 + 1,
                width: size - 2,
                height: size - 2
            )),
            with: .color(look.accent.opacity(0.85)),
            lineWidth: 2
        )
    }
}

private func drawWheelCombo(
    into context: inout GraphicsContext,
    canvasSize: CGSize,
    size: CGFloat,
    comboFractions: [Double],
    comboTracks: [Bool],
    comboSpins: [Double],
    look: ThemeLook,
    stage: MinerStage
) {
    let g = WheelGeom(
        canvasSize: canvasSize,
        size: size,
        comboFractions: comboFractions,
        comboTracks: comboTracks,
        stage: stage
    )
    let fracs = [
        comboFractions.count > 0 ? comboFractions[0] : 0,
        comboFractions.count > 1 ? comboFractions[1] : 0,
        comboFractions.count > 2 ? comboFractions[2] : 0,
    ]
    let spin0 = comboSpins.count > 0 ? comboSpins[0] : 0
    for ring in 0..<3 {
        drawComboBand(
            into: &context,
            center: g.center,
            pad: g.pads[ring],
            rim: g.comboRim,
            size: size,
            frac: fracs[ring],
            fill: look.comboFill(ring),
            showTicks: ring == 0 && (g.shown[0] || fracs[0] > 0.001),
            spinTurns: ring == 0 ? spin0 : 0
        )
    }
}

private func drawWheelHub(
    into context: inout GraphicsContext,
    canvasSize: CGSize,
    size: CGFloat,
    flash: Bool,
    look: ThemeLook,
    stage: MinerStage
) {
    let g = WheelGeom(canvasSize: canvasSize, size: size, comboFractions: [0, 0, 0], comboTracks: [true, false, false], stage: stage)
    let chrome = g.chrome
    let center = g.center
    let ink = Color("BrandInk")

    var pointer = Path()
    let tipY = center.y - size * 0.5 + 4
    pointer.move(to: CGPoint(x: center.x, y: tipY))
    pointer.addLine(to: CGPoint(x: center.x + 7, y: tipY + 12))
    pointer.addLine(to: CGPoint(x: center.x - 7, y: tipY + 12))
    pointer.closeSubpath()
    context.fill(pointer, with: .color(flash ? look.accent : ink.opacity(chrome.pointer)))

    let plate = CGRect(x: center.x + size * 0.5 - 4.5, y: center.y - 13, width: 9, height: 26)
    let platePath = Path(roundedRect: plate, cornerRadius: 3, style: .continuous)
    context.fill(platePath, with: .color(ink.opacity(chrome.plate)))
    context.stroke(platePath, with: .color(ink.opacity(min(1, chrome.plate + 0.12))), lineWidth: 1)
}

private func drawComboBand(
    into context: inout GraphicsContext,
    center: CGPoint,
    pad: CGFloat,
    rim: CGFloat,
    size: CGFloat,
    frac: Double,
    fill: Color,
    showTicks: Bool,
    spinTurns: Double
) {
    let radius = size / 2 - pad
    let drawArc = frac > 0.001
    guard showTicks || drawArc else { return }
    if drawArc {
        let sweep = min(1, max(0, frac))
        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + sweep * 360),
            clockwise: false
        )
        context.stroke(
            arc,
            with: .color(fill.opacity(sweep < 0.18 ? 0.42 : 0.22)),
            style: StrokeStyle(lineWidth: rim * (sweep < 0.18 ? 1.55 : 1.25), lineCap: .round)
        )
        context.stroke(
            arc,
            with: .color(fill),
            style: StrokeStyle(lineWidth: rim * 0.70, lineCap: .round)
        )
    }
    guard showTicks else { return }
    let tick = Color(red: 244 / 255, green: 245 / 255, blue: 250 / 255)
    let spinDeg = spinTurns * 360
    let tickOuter = radius + rim * 0.36
    var minor = Path()
    appendTicks(&minor, center: center, count: 24, startDeg: spinDeg - 90, stepDeg: 15, outer: tickOuter, length: rim * 0.55)
    context.stroke(minor, with: .color(tick.opacity(0.78)), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
    var major = Path()
    appendTicks(&major, center: center, count: 8, startDeg: spinDeg - 90, stepDeg: 45, outer: tickOuter, length: rim * 0.95)
    context.stroke(major, with: .color(tick.opacity(0.94)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
}

private func appendTicks(
    _ path: inout Path,
    center: CGPoint,
    count: Int,
    startDeg: Double,
    stepDeg: Double,
    outer: CGFloat,
    length: CGFloat
) {
    var a = startDeg * .pi / 180
    let step = stepDeg * .pi / 180
    for _ in 0..<count {
        let cosA = CGFloat(cos(a))
        let sinA = CGFloat(sin(a))
        path.move(to: CGPoint(x: center.x + cosA * (outer - length), y: center.y + sinA * (outer - length)))
        path.addLine(to: CGPoint(x: center.x + cosA * outer, y: center.y + sinA * outer))
        a += step
    }
}

private func fillCircle(
    _ context: inout GraphicsContext,
    center: CGPoint,
    radius: CGFloat,
    color: Color
) {
    context.fill(
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )),
        with: .color(color)
    )
}
