import SwiftUI

struct BrandMarkView: View {
    var width: CGFloat
    var routeColor: Color = ProductivityTheme.accentTertiary
    var activeColor: Color = ProductivityTheme.accent
    var dotColor: Color = ProductivityTheme.accentSecondary

    private var height: CGFloat {
        width * (248.0 / 312.0)
    }

    var body: some View {
        ZStack {
            SequenceRouteShape()
                .stroke(
                    routeColor,
                    style: StrokeStyle(
                        lineWidth: height * (48.0 / 248.0),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            SequenceActiveStageShape()
                .stroke(
                    activeColor,
                    style: StrokeStyle(
                        lineWidth: height * (48.0 / 248.0),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            Circle()
                .fill(dotColor)
                .frame(width: height * (48.0 / 248.0), height: height * (48.0 / 248.0))
                .offset(x: width * 0.3846, y: height * 0.3145)
        }
        .frame(width: width, height: height)
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

private struct SequenceRouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX: CGFloat = 112
        let maxX: CGFloat = 424
        let minY: CGFloat = 144
        let maxY: CGFloat = 392
        let scaleX = rect.width / (maxX - minX)
        let scaleY = rect.height / (maxY - minY)

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (x - minX) * scaleX, y: (y - minY) * scaleY)
        }

        path.move(to: point(112, 144))
        path.addLine(to: point(344, 144))
        path.addCurve(
            to: point(400, 200),
            control1: point(374.93, 144),
            control2: point(400, 169.07)
        )
        path.addCurve(
            to: point(344, 256),
            control1: point(400, 230.93),
            control2: point(374.93, 256)
        )
        path.addLine(to: point(168, 256))
        path.addCurve(
            to: point(112, 312),
            control1: point(137.07, 256),
            control2: point(112, 281.07)
        )
        path.addCurve(
            to: point(168, 368),
            control1: point(112, 342.93),
            control2: point(137.07, 368)
        )
        path.addLine(to: point(344, 368))
        return path
    }
}

private struct SequenceActiveStageShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX: CGFloat = 112
        let maxX: CGFloat = 424
        let minY: CGFloat = 144
        let maxY: CGFloat = 392
        let scaleX = rect.width / (maxX - minX)
        let scaleY = rect.height / (maxY - minY)
        path.move(to: CGPoint(x: (112 - minX) * scaleX, y: (144 - minY) * scaleY))
        path.addLine(to: CGPoint(x: (224 - minX) * scaleX, y: (144 - minY) * scaleY))
        return path
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 24) {
        BrandMarkView(width: 150)
        BrandMarkView(
            width: 150,
            routeColor: .white,
            activeColor: ProductivityTheme.accent,
            dotColor: ProductivityTheme.accentSecondary
        )
        .padding(28)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 20))
    }
    .padding(30)
    .background(ProductivityTheme.background)
}
#endif
