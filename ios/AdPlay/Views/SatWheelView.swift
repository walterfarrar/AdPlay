import SwiftUI

/// Sat wheel chrome. Drawn in one Canvas so 60 fps combo / Stronger taps
/// do not rebuild hundreds of Capsule views.
struct SatWheelView: View {
    let fraction: Double
    var flash: Bool = false
    var comboFractions: [Double] = [0, 0, 0]
    var comboTracks: [Bool] = [true, false, false]
    var comboMultiplier: Double = 1
    var look: ThemeLook = .ember

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let comboLabel = ComboEngine.formatMultiplier(comboMultiplier)
            ZStack {
                Canvas { context, canvasSize in
                    drawSatWheel(
                        into: &context,
                        canvasSize: canvasSize,
                        size: size,
                        fraction: fraction,
                        flash: flash,
                        comboFractions: comboFractions,
                        comboTracks: comboTracks,
                        comboMultiplier: comboMultiplier,
                        look: look
                    )
                }
                if !comboLabel.isEmpty {
                    Text(comboLabel)
                        .font(.system(size: size * 0.07, weight: .bold, design: .rounded))
                        .foregroundStyle(look.combo)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private func drawSatWheel(
    into context: inout GraphicsContext,
    canvasSize: CGSize,
    size: CGFloat,
    fraction: Double,
    flash: Bool,
    comboFractions: [Double],
    comboTracks: [Bool],
    comboMultiplier: Double,
    look: ThemeLook
) {
    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    let rim = size * 0.06
    let radius = size / 2 - rim / 2
    let comboRim = rim * 0.50
    let comboPitch = comboRim * 1.35
    let pad0 = rim * 1.15
    let pad1 = pad0 + comboPitch
    let pad2 = pad0 + comboPitch * 2
    let pads = [pad0, pad1, pad2]
    let fracs = [
        comboFractions.count > 0 ? comboFractions[0] : 0,
        comboFractions.count > 1 ? comboFractions[1] : 0,
        comboFractions.count > 2 ? comboFractions[2] : 0,
    ]
    let shown = [
        (comboTracks.count > 0 ? comboTracks[0] : true) || fracs[0] > 0.001,
        (comboTracks.count > 1 ? comboTracks[1] : false) || fracs[1] > 0.001,
        (comboTracks.count > 2 ? comboTracks[2] : false) || fracs[2] > 0.001,
    ]
    let innerIdx = shown[2] ? 2 : (shown[1] ? 1 : 0)
    let innerRadius = size / 2 - pads[innerIdx]
    let pegOrbit = max(size * 0.16, innerRadius - comboRim * 0.55 - 5)
    let ink = Color("BrandInk")
    let frac = min(1, max(0, fraction))

    let track = Path(ellipseIn: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
    context.stroke(track, with: .color(ink.opacity(0.08)), lineWidth: rim)

    if frac > 0.0005 {
        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + frac * 360),
            clockwise: false
        )
        var glow = context
        glow.addFilter(.shadow(
            color: (flash ? look.accent : look.fill).opacity(flash ? 0.9 : 0.45),
            radius: flash ? 16 : 8
        ))
        glow.stroke(
            arc,
            with: .linearGradient(
                Gradient(colors: flash
                    ? [look.accent, Color.white, look.accent]
                    : [look.fill, look.fillHot, look.fill]),
                startPoint: CGPoint(x: center.x, y: center.y - radius),
                endPoint: CGPoint(x: center.x, y: center.y + radius)
            ),
            style: StrokeStyle(lineWidth: rim, lineCap: .round)
        )
    }

    context.drawLayer { face in
        face.translateBy(x: center.x, y: center.y)
        face.rotate(by: .degrees(frac * 360))
        face.translateBy(x: -center.x, y: -center.y)
        let faceR = size * 0.48 - rim * 0.85
        face.fill(
            Path(ellipseIn: CGRect(
                x: center.x - faceR,
                y: center.y - faceR,
                width: faceR * 2,
                height: faceR * 2
            )),
            with: .radialGradient(
                Gradient(colors: [ink.opacity(0.04), ink.opacity(0.10)]),
                center: center,
                startRadius: 0,
                endRadius: size * 0.48
            )
        )
        for i in 0..<60 {
            strokeTick(
                into: &face,
                center: center,
                angleDeg: Double(i) * 6 - 90,
                outer: size * 0.365,
                length: 5,
                width: 0.8,
                color: ink.opacity(0.10)
            )
        }
        for i in 0..<12 {
            let major = i % 3 == 0
            strokeTick(
                into: &face,
                center: center,
                angleDeg: Double(i) * 30 - 90,
                outer: size * 0.38,
                length: major ? 14 : 9,
                width: major ? 3 : 2,
                color: ink.opacity(major ? 0.35 : 0.16)
            )
        }
    }

    for ring in 0..<3 {
        drawComboBand(
            into: &context,
            center: center,
            pad: pads[ring],
            rim: comboRim,
            size: size,
            frac: fracs[ring],
            showTrack: shown[ring],
            fill: look.comboFill(ring),
            trackOpacity: 0.10 + Double(ring) * 0.04,
            tickCount: ring == 0 ? 60 : (ring == 1 ? 48 : 36),
            ink: ink
        )
    }

    if shown[innerIdx] {
        for i in 0..<18 {
            strokeTick(
                into: &context,
                center: center,
                angleDeg: Double(i) * 20 - 90,
                outer: innerRadius - comboRim * 0.32,
                length: comboRim * 0.5,
                width: 1.3,
                color: ink.opacity(0.30)
            )
        }
    }

    let pegAngle = (frac * 360 - 90) * .pi / 180
    let peg = CGPoint(
        x: center.x + cos(pegAngle) * pegOrbit,
        y: center.y + sin(pegAngle) * pegOrbit
    )
    fillCircle(&context, center: peg, radius: 5, color: ink.opacity(0.55))
    fillCircle(&context, center: peg, radius: 3.5, color: look.accent.opacity(0.95))
    fillCircle(
        &context,
        center: CGPoint(x: peg.x - 1.1, y: peg.y - 1.1),
        radius: 1.2,
        color: Color.white.opacity(0.35)
    )

    var pointer = Path()
    let tipY = center.y - size * 0.5 + 4
    pointer.move(to: CGPoint(x: center.x, y: tipY))
    pointer.addLine(to: CGPoint(x: center.x + 7, y: tipY + 12))
    pointer.addLine(to: CGPoint(x: center.x - 7, y: tipY + 12))
    pointer.closeSubpath()
    context.fill(pointer, with: .color(flash ? look.accent : ink.opacity(0.75)))

    let plate = CGRect(x: center.x + size * 0.5 - 4.5, y: center.y - 13, width: 9, height: 26)
    let platePath = Path(roundedRect: plate, cornerRadius: 3, style: .continuous)
    context.fill(platePath, with: .color(ink.opacity(0.30)))
    context.stroke(platePath, with: .color(ink.opacity(0.35)), lineWidth: 1)

    let hubR = size * 0.14
    context.fill(
        Path(ellipseIn: CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2)),
        with: .linearGradient(
            Gradient(colors: [ink.opacity(0.12), ink.opacity(0.06)]),
            startPoint: CGPoint(x: center.x, y: center.y - hubR),
            endPoint: CGPoint(x: center.x, y: center.y + hubR)
        )
    )
    context.stroke(
        Path(ellipseIn: CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2)),
        with: .color(ink.opacity(0.12)),
        lineWidth: 1
    )
    if ComboEngine.formatMultiplier(comboMultiplier).isEmpty {
        fillCircle(
            &context,
            center: center,
            radius: size * 0.04,
            color: look.accent.opacity(flash ? 0.55 : 0.2)
        )
    }

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

private func drawComboBand(
    into context: inout GraphicsContext,
    center: CGPoint,
    pad: CGFloat,
    rim: CGFloat,
    size: CGFloat,
    frac: Double,
    showTrack: Bool,
    fill: Color,
    trackOpacity: Double,
    tickCount: Int,
    ink: Color
) {
    let radius = size / 2 - pad
    let drawArc = frac > 0.001
    guard showTrack || drawArc else { return }
    let ring = Path(ellipseIn: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
    context.stroke(ring, with: .color(ink.opacity(0.22)), lineWidth: rim * 1.22)
    context.stroke(ring, with: .color(ink.opacity(trackOpacity)), lineWidth: rim)
    let majorEvery = max(1, tickCount / 12)
    for i in 0..<tickCount {
        let major = i % majorEvery == 0
        strokeTick(
            into: &context,
            center: center,
            angleDeg: Double(i) * 360 / Double(tickCount) - 90,
            outer: radius + (major ? rim * 0.44 : rim * 0.21),
            length: major ? rim * 0.88 : rim * 0.42,
            width: major ? 1.5 : 0.7,
            color: ink.opacity(major ? 0.32 : 0.11)
        )
    }
    for i in 0..<4 {
        let a = (Double(i) * 90 - 90) * .pi / 180
        let rivetR = radius - rim * 0.12
        fillCircle(
            &context,
            center: CGPoint(x: center.x + cos(a) * rivetR, y: center.y + sin(a) * rivetR),
            radius: 1.55,
            color: ink.opacity(0.42)
        )
    }
    guard drawArc else { return }
    let sweep = min(1, max(0, frac))
    let fresh = sweep < 0.18
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
        with: .color(fill.opacity(fresh ? 0.42 : 0.22)),
        style: StrokeStyle(lineWidth: rim * (fresh ? 1.85 : 1.55), lineCap: .round)
    )
    context.stroke(
        arc,
        with: .color(ink.opacity(0.38)),
        style: StrokeStyle(lineWidth: rim, lineCap: .round)
    )
    context.stroke(
        arc,
        with: .color(fill),
        style: StrokeStyle(lineWidth: rim * 0.70, lineCap: .round)
    )
}

private func strokeTick(
    into context: inout GraphicsContext,
    center: CGPoint,
    angleDeg: Double,
    outer: CGFloat,
    length: CGFloat,
    width: CGFloat,
    color: Color
) {
    let a = angleDeg * .pi / 180
    let cosA = CGFloat(cos(a))
    let sinA = CGFloat(sin(a))
    var path = Path()
    path.move(to: CGPoint(x: center.x + cosA * (outer - length), y: center.y + sinA * (outer - length)))
    path.addLine(to: CGPoint(x: center.x + cosA * outer, y: center.y + sinA * outer))
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
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
