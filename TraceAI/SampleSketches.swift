import UIKit

/// Three built-in sketches drawn in code (no image assets).
/// Each sketch has 4 stroke groups (construction shapes → outline → details → hatching),
/// drawn in a 1000×1000 design space and scaled to fit the requested size.
enum SampleSketch: String, CaseIterable, Identifiable, Sendable {
    case cat, flower, house

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cat: "Cat"
        case .flower: "Flower"
        case .house: "House"
        }
    }

    func makeStencilSet(size: CGSize = CGSize(width: 1024, height: 1024)) -> StencilSet {
        let groups = strokeGroups
        let layers = (1...4).map { Self.render(groups.prefix($0), size: size) }
        return StencilSet(full: layers[2], layers: layers)   // full = shapes + outline + details
    }

    private var strokeGroups: [StrokeGroup] {
        switch self {
        case .cat: Self.catGroups
        case .flower: Self.flowerGroups
        case .house: Self.houseGroups
        }
    }

    private static func render(_ groups: ArraySlice<StrokeGroup>, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let unit = min(size.width, size.height) / 1000
            cg.translateBy(x: (size.width - 1000 * unit) / 2, y: (size.height - 1000 * unit) / 2)
            cg.scaleBy(x: unit, y: unit)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for group in groups {
                cg.saveGState()
                cg.setStrokeColor(UIColor.black.withAlphaComponent(group.alpha).cgColor)
                cg.setLineWidth(group.width)
                group.draw(cg)
                cg.restoreGState()
            }
        }
    }

    // MARK: Cat face

    private static var catGroups: [StrokeGroup] {
        let head = path { p in
            p.move(to: pt(290, 390)); p.addLine(to: pt(300, 165)); p.addLine(to: pt(430, 300))
            p.addQuadCurve(to: pt(570, 300), control: pt(500, 275))
            p.addLine(to: pt(700, 165)); p.addLine(to: pt(710, 390))
            p.addQuadCurve(to: pt(740, 620), control: pt(780, 480))
            p.addQuadCurve(to: pt(500, 790), control: pt(700, 780))
            p.addQuadCurve(to: pt(260, 620), control: pt(300, 780))
            p.addQuadCurve(to: pt(290, 390), control: pt(220, 480))
            p.closeSubpath()
        }
        let innerEars = [poly([pt(320, 330), pt(315, 215), pt(395, 300)]),
                         poly([pt(680, 330), pt(685, 215), pt(605, 300)])]
        return [
            StrokeGroup(width: 3, alpha: 0.45) { cg in
                cg.stroke(ellipse(500, 540, 260, 240),
                          poly([pt(285, 400), pt(300, 160), pt(440, 310)]),
                          poly([pt(715, 400), pt(700, 160), pt(560, 310)]),
                          line(pt(500, 280), pt(500, 800)), line(pt(260, 510), pt(740, 510)))
            },
            StrokeGroup(width: 9) { cg in cg.stroke(head) },
            StrokeGroup(width: 6) { cg in
                cg.stroke(ellipse(405, 510, 50, 38), ellipse(595, 510, 50, 38),
                          ellipse(405, 510, 12, 30), ellipse(595, 510, 12, 30),
                          poly([pt(470, 590), pt(530, 590), pt(500, 625)]))
                cg.stroke(innerEars)
                cg.stroke(path { p in
                    p.move(to: pt(500, 625)); p.addLine(to: pt(500, 650))
                    p.addQuadCurve(to: pt(445, 670), control: pt(475, 685))
                    p.move(to: pt(500, 650)); p.addQuadCurve(to: pt(555, 670), control: pt(525, 685))
                })
                let whiskers: [(CGPoint, CGPoint)] = [(pt(380, 620), pt(230, 590)),
                                                      (pt(380, 640), pt(225, 650)),
                                                      (pt(385, 660), pt(240, 705))]
                for (a, b) in whiskers {
                    cg.stroke(line(a, b), line(pt(1000 - a.x, a.y), pt(1000 - b.x, b.y)))
                }
            },
            StrokeGroup(width: 3) { cg in
                for ear in innerEars { cg.hatch([ear], spacing: 14, angle: .pi / 4) }
                cg.hatch([head, rect(300, 700, 400, 120)], spacing: 14, angle: .pi / 4)
                cg.hatch([head, ellipse(720, 590, 70, 110)], spacing: 16, angle: .pi / 3)
            },
        ]
    }

    // MARK: Flower

    private static var flowerGroups: [StrokeGroup] {
        let center = pt(500, 370)
        func around(_ p: CGPath, _ i: Int) -> CGPath {
            var t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: CGFloat(i) * .pi / 3)
            return p.copy(using: &t) ?? p
        }
        let petal = path { p in
            p.move(to: pt(0, -70))
            p.addCurve(to: pt(0, -235), control1: pt(-120, -110), control2: pt(-70, -235))
            p.addCurve(to: pt(0, -70), control1: pt(70, -235), control2: pt(120, -110))
        }
        let leftLeaf = path { p in
            p.move(to: pt(495, 780)); p.addQuadCurve(to: pt(320, 690), control: pt(420, 660))
            p.addQuadCurve(to: pt(495, 780), control: pt(380, 790)); p.closeSubpath()
        }
        let rightLeaf = path { p in
            p.move(to: pt(515, 840)); p.addQuadCurve(to: pt(690, 750), control: pt(590, 720))
            p.addQuadCurve(to: pt(515, 840), control: pt(630, 850)); p.closeSubpath()
        }
        let disc = ellipse(500, 370, 70, 70)
        return [
            StrokeGroup(width: 3, alpha: 0.45) { cg in
                cg.stroke(ellipse(500, 370, 235, 235), disc, line(pt(500, 600), pt(500, 920)),
                          line(pt(495, 780), pt(320, 690)), line(pt(515, 840), pt(690, 750)))
            },
            StrokeGroup(width: 9) { cg in
                cg.stroke((0..<6).map { around(petal, $0) })
                cg.stroke(disc, leftLeaf, rightLeaf, line(pt(380, 920), pt(620, 920)))
                cg.stroke(path { p in
                    p.move(to: pt(493, 605)); p.addQuadCurve(to: pt(490, 920), control: pt(520, 760))
                    p.move(to: pt(507, 605)); p.addQuadCurve(to: pt(510, 920), control: pt(534, 760))
                })
            },
            StrokeGroup(width: 5) { cg in
                cg.stroke((0..<6).map { around(line(pt(0, -95), pt(0, -190)), $0) })
                var seeds = [ellipse(500, 370, 7, 7)]
                for ring in [(r: CGFloat(26), n: 6), (r: CGFloat(50), n: 10)] {
                    for k in 0..<ring.n {
                        let a = CGFloat(k) * 2 * .pi / CGFloat(ring.n)
                        seeds.append(ellipse(500 + ring.r * cos(a), 370 + ring.r * sin(a), 7, 7))
                    }
                }
                cg.stroke(seeds)
                cg.stroke(path { p in
                    p.move(to: pt(495, 780)); p.addQuadCurve(to: pt(335, 695), control: pt(410, 725))
                    p.move(to: pt(515, 840)); p.addQuadCurve(to: pt(675, 755), control: pt(600, 790))
                })
            },
            StrokeGroup(width: 3) { cg in
                cg.hatch([disc, rect(420, 380, 160, 80)], spacing: 12, angle: .pi / 4)
                cg.hatch([leftLeaf, rect(300, 730, 200, 80)], spacing: 14, angle: -.pi / 4)
                cg.hatch([rightLeaf, rect(510, 785, 200, 80)], spacing: 14, angle: .pi / 4)
                for i in 0..<6 { cg.hatch([around(petal, i), around(rect(10, -240, 120, 120), i)],
                                          spacing: 16, angle: .pi / 2 + CGFloat(i) * .pi / 3) }
            },
        ]
    }

    // MARK: House

    private static var houseGroups: [StrokeGroup] {
        let roof = poly([pt(200, 490), pt(500, 210), pt(800, 490)])
        let chimney = poly([pt(620, 322), pt(620, 230), pt(690, 230), pt(690, 387)])
        let door = rect(445, 650, 110, 200)
        let windows = [rect(300, 560, 110, 100), rect(590, 560, 110, 100)]
        return [
            StrokeGroup(width: 3, alpha: 0.45) { cg in
                cg.stroke(rect(260, 470, 480, 380), poly([pt(220, 480), pt(500, 220), pt(780, 480)]),
                          line(pt(150, 850), pt(850, 850)), rect(445, 640, 110, 210))
            },
            StrokeGroup(width: 9) { cg in
                cg.stroke(roof, poly([pt(620, 325), pt(620, 230), pt(690, 230), pt(690, 390)], closed: false),
                          poly([pt(260, 490), pt(260, 850), pt(740, 850), pt(740, 490)], closed: false),
                          poly([pt(445, 850), pt(445, 650), pt(555, 650), pt(555, 850)], closed: false),
                          line(pt(150, 850), pt(850, 850)))
            },
            StrokeGroup(width: 5) { cg in
                cg.stroke(windows)
                for w in windows.map(\.boundingBoxOfPath) {
                    cg.stroke(line(pt(w.midX, w.minY), pt(w.midX, w.maxY)), line(pt(w.minX, w.midY), pt(w.maxX, w.midY)),
                              line(pt(w.minX - 10, w.maxY + 8), pt(w.maxX + 10, w.maxY + 8)))
                }
                cg.stroke(ellipse(535, 760, 8, 8), line(pt(610, 230), pt(700, 230)))
                for y in stride(from: CGFloat(290), through: 450, by: 55) {
                    let half = (y - 210) * 300 / 280 - 20
                    cg.stroke(line(pt(500 - half, y), pt(500 + half, y)))
                }
            },
            StrokeGroup(width: 3) { cg in
                cg.hatch([door], spacing: 14, angle: .pi / 4)
                cg.hatch([chimney], spacing: 14, angle: .pi / 4)
                cg.hatch([rect(260, 490, 480, 35)], spacing: 10, angle: .pi / 2)
                cg.hatch([rect(690, 525, 50, 325)], spacing: 14, angle: .pi / 3)
                for w in windows { cg.hatch([w], spacing: 20, angle: -.pi / 4) }
            },
        ]
    }
}

// MARK: - Drawing helpers

private struct StrokeGroup {
    var width: CGFloat
    var alpha: CGFloat = 1
    var draw: (CGContext) -> Void
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private func path(_ build: (CGMutablePath) -> Void) -> CGPath {
    let p = CGMutablePath()
    build(p)
    return p
}

private func line(_ a: CGPoint, _ b: CGPoint) -> CGPath { poly([a, b], closed: false) }

private func poly(_ points: [CGPoint], closed: Bool = true) -> CGPath {
    path { p in
        p.addLines(between: points)
        if closed { p.closeSubpath() }
    }
}

private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    CGPath(rect: CGRect(x: x, y: y, width: w, height: h), transform: nil)
}

private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry), transform: nil)
}

private extension CGContext {
    func stroke(_ paths: CGPath...) { stroke(paths) }

    func stroke(_ paths: [CGPath]) {
        for p in paths { addPath(p) }
        strokePath()
    }

    /// Parallel lines at `angle` (radians), clipped to the intersection of `clips`.
    func hatch(_ clips: [CGPath], spacing: CGFloat, angle: CGFloat) {
        guard let first = clips.first else { return }
        saveGState()
        for c in clips { addPath(c); clip() }
        let box = first.boundingBoxOfPath
        let r = hypot(box.width, box.height) / 2
        let (dx, dy) = (cos(angle), sin(angle))
        let lines = CGMutablePath()
        for offset in stride(from: -r, through: r, by: spacing) {
            let base = CGPoint(x: box.midX - dy * offset, y: box.midY + dx * offset)
            lines.move(to: CGPoint(x: base.x - dx * r, y: base.y - dy * r))
            lines.addLine(to: CGPoint(x: base.x + dx * r, y: base.y + dy * r))
        }
        addPath(lines)
        strokePath()
        restoreGState()
    }
}
