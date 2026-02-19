import SwiftUI
import Combine
import UIKit

enum CalculatorLayoutMode: Equatable {
    case portrait
    case landscapeLeft
    case landscapeRight

    var isScientific: Bool {
        switch self {
        case .portrait:
            return false
        case .landscapeLeft, .landscapeRight:
            return true
        }
    }

    var rotationAngle: Angle {
        switch self {
        case .portrait:
            return .degrees(0)
        case .landscapeLeft:
            return .degrees(90)
        case .landscapeRight:
            return .degrees(-90)
        }
    }
}

enum CalculatorKeyRole: Hashable {
    case input(CalculatorInput)
    case clearDynamic
    case angleDynamic
}

enum CalculatorKeyVisualStyle: Hashable {
    case topFunction
    case midFunction
    case number
    case operatorKey
    case equals
    case accent
}

struct CalculatorKeySpec: Identifiable, Hashable {
    let id: String
    let primaryTitle: String
    let secondaryTitle: String?
    let primaryRole: CalculatorKeyRole
    let secondaryRole: CalculatorKeyRole?
    let row: Int
    let column: Int
    let rowSpan: Int
    let columnSpan: Int
    let rowWeight: CGFloat
    let style: CalculatorKeyVisualStyle
    let fontSize: CGFloat

    init(
        id: String,
        primaryTitle: String,
        secondaryTitle: String? = nil,
        primaryRole: CalculatorKeyRole,
        secondaryRole: CalculatorKeyRole? = nil,
        row: Int,
        column: Int,
        rowSpan: Int = 1,
        columnSpan: Int = 1,
        rowWeight: CGFloat = 1.0,
        style: CalculatorKeyVisualStyle,
        fontSize: CGFloat
    ) {
        self.id = id
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.primaryRole = primaryRole
        self.secondaryRole = secondaryRole
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
        self.rowWeight = rowWeight
        self.style = style
        self.fontSize = fontSize
    }

    func resolvedTitle(useSecondary: Bool, clearTitle: String, angleToggleTitle: String) -> String {
        switch primaryRole {
        case .clearDynamic:
            return clearTitle
        case .angleDynamic:
            return angleToggleTitle
        default:
            break
        }

        if useSecondary, let secondaryTitle {
            return secondaryTitle
        }

        return primaryTitle
    }

    func resolvedRole(useSecondary: Bool) -> CalculatorKeyRole {
        if useSecondary, let secondaryRole {
            return secondaryRole
        }
        return primaryRole
    }
}

@MainActor
final class CalculatorViewModel: ObservableObject {
    @Published private(set) var layoutMode: CalculatorLayoutMode = .portrait
    @Published private(set) var displayText = "0"
    @Published private(set) var isSecondActive = false
    @Published private(set) var angleBadgeText = AngleUnit.radians.rawValue
    @Published private(set) var clearTitle = "AC"

    private var engine = CalculatorEngine()

    var angleToggleTitle: String {
        engine.state.angleUnit == .radians ? "Deg" : "Rad"
    }

    var useSecondaryLabels: Bool {
        isSecondActive
    }

    func onAppear() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        syncFromEngine()
        updateLayout(for: UIDevice.current.orientation)
    }

    func onDisappear() {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    func updateLayout(for orientation: UIDeviceOrientation) {
        let newMode: CalculatorLayoutMode
        switch orientation {
        case .landscapeLeft:
            newMode = .landscapeLeft
        case .landscapeRight:
            newMode = .landscapeRight
        case .portrait, .portraitUpsideDown:
            newMode = .portrait
        default:
            return
        }

        guard newMode != layoutMode else { return }
        layoutMode = newMode
        engine.setScientificMode(newMode.isScientific)
        syncFromEngine()
    }

    func perform(_ role: CalculatorKeyRole) {
        switch role {
        case .input(let input):
            engine.apply(input)
        case .clearDynamic:
            if engine.state.canUseClearEntry {
                engine.apply(.clearEntry)
            } else {
                engine.apply(.allClear)
            }
        case .angleDynamic:
            engine.apply(.toggleAngleUnit)
        }

        syncFromEngine()
    }

    private func syncFromEngine() {
        displayText = engine.state.displayText
        isSecondActive = engine.state.isSecondActive
        angleBadgeText = engine.state.angleUnit.rawValue
        clearTitle = engine.state.canUseClearEntry ? "C" : "AC"
    }
}

struct Calculator: View {
    @StateObject private var viewModel = CalculatorViewModel()
    private let orientationPublisher = NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                calculatorBackground

                if viewModel.layoutMode.isScientific {
                    scientificBody(geometry: geometry)
                } else {
                    portraitBody
                }
            }
            .clipped()
            .onAppear {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
            .onReceive(orientationPublisher) { _ in
                viewModel.updateLayout(for: UIDevice.current.orientation)
            }
        }
    }

    private var calculatorBackground: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 53/255, green: 54/255, blue: 57/255), location: 0),
                    .init(color: Color(red: 32/255, green: 33/255, blue: 36/255), location: 0.5),
                    .init(color: Color(red: 24/255, green: 24/255, blue: 26/255), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )

            Image("FolderSwitcherBG")
                .resizable(capInsets: EdgeInsets(), resizingMode: .tile)
                .opacity(0.2)
        }
    }

    private var portraitBody: some View {
        VStack(spacing: 0) {
            status_bar()
                .frame(minHeight: 24, maxHeight: 24)

            CalculatorDisplayView(
                text: viewModel.displayText,
                angleBadge: nil,
                scientific: false
            )
            .frame(height: 180)

            CalculatorKeyGrid(
                rows: 6,
                columns: 4,
                spacing: 12,
                keys: portraitKeys,
                useSecondary: viewModel.useSecondaryLabels,
                clearTitle: viewModel.clearTitle,
                angleToggleTitle: viewModel.angleToggleTitle,
                onTap: viewModel.perform,
                secondIsActive: viewModel.isSecondActive,
                compactRows: true
            )
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
    }

    private func scientificBody(geometry: GeometryProxy) -> some View {
        // The canvas is laid out in landscape orientation (width/height swapped),
        // then rotated 90 degrees to fit the portrait-locked container.
        let canvasWidth = max(geometry.size.height, 10)
        let canvasHeight = max(geometry.size.width, 10)

        return ScientificCanvasView(
            displayText: viewModel.displayText,
            angleBadge: viewModel.angleBadgeText,
            keys: scientificKeys,
            useSecondary: viewModel.useSecondaryLabels,
            clearTitle: viewModel.clearTitle,
            angleToggleTitle: viewModel.angleToggleTitle,
            secondIsActive: viewModel.isSecondActive,
            onTap: viewModel.perform
        )
        .frame(width: canvasWidth, height: canvasHeight)
        .rotationEffect(viewModel.layoutMode.rotationAngle)
        .frame(width: geometry.size.width, height: geometry.size.height)
    }

    private var portraitKeys: [CalculatorKeySpec] {
        [
            CalculatorKeySpec(id: "mc", primaryTitle: "mc", primaryRole: .input(.memoryClear), row: 0, column: 0, style: .topFunction, fontSize: 32/2),
            CalculatorKeySpec(id: "m+", primaryTitle: "m+", primaryRole: .input(.memoryAdd), row: 0, column: 1, style: .topFunction, fontSize: 32/2),
            CalculatorKeySpec(id: "m-", primaryTitle: "m-", primaryRole: .input(.memorySubtract), row: 0, column: 2, style: .topFunction, fontSize: 32/2),
            CalculatorKeySpec(id: "mr", primaryTitle: "mr", primaryRole: .input(.memoryRecall), row: 0, column: 3, style: .topFunction, fontSize: 32/2),

            CalculatorKeySpec(id: "clear", primaryTitle: "AC", primaryRole: .clearDynamic, row: 1, column: 0, style: .midFunction, fontSize: 22),
            CalculatorKeySpec(id: "sign", primaryTitle: "+/-", primaryRole: .input(.toggleSign), row: 1, column: 1, style: .midFunction, fontSize: 22),
            CalculatorKeySpec(id: "divide", primaryTitle: "÷", primaryRole: .input(.binary(.divide)), row: 1, column: 2, style: .operatorKey, fontSize: 32),
            CalculatorKeySpec(id: "multiply", primaryTitle: "×", primaryRole: .input(.binary(.multiply)), row: 1, column: 3, style: .operatorKey, fontSize: 30),

            CalculatorKeySpec(id: "7", primaryTitle: "7", primaryRole: .input(.digit(7)), row: 2, column: 0, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "8", primaryTitle: "8", primaryRole: .input(.digit(8)), row: 2, column: 1, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "9", primaryTitle: "9", primaryRole: .input(.digit(9)), row: 2, column: 2, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "minus", primaryTitle: "−", primaryRole: .input(.binary(.subtract)), row: 2, column: 3, style: .operatorKey, fontSize: 34),

            CalculatorKeySpec(id: "4", primaryTitle: "4", primaryRole: .input(.digit(4)), row: 3, column: 0, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "5", primaryTitle: "5", primaryRole: .input(.digit(5)), row: 3, column: 1, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "6", primaryTitle: "6", primaryRole: .input(.digit(6)), row: 3, column: 2, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "plus", primaryTitle: "+", primaryRole: .input(.binary(.add)), row: 3, column: 3, style: .operatorKey, fontSize: 34),

            CalculatorKeySpec(id: "1", primaryTitle: "1", primaryRole: .input(.digit(1)), row: 4, column: 0, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "2", primaryTitle: "2", primaryRole: .input(.digit(2)), row: 4, column: 1, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "3", primaryTitle: "3", primaryRole: .input(.digit(3)), row: 4, column: 2, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "equals", primaryTitle: "=", primaryRole: .input(.equals), row: 4, column: 3, rowSpan: 2, style: .equals, fontSize: 42),

            CalculatorKeySpec(id: "0", primaryTitle: "0", primaryRole: .input(.digit(0)), row: 5, column: 0, columnSpan: 2, style: .number, fontSize: 34),
            CalculatorKeySpec(id: "dot", primaryTitle: ".", primaryRole: .input(.decimalPoint), row: 5, column: 2, style: .number, fontSize: 40)
        ]
    }

    private var scientificKeys: [CalculatorKeySpec] {
        [
            CalculatorKeySpec(id: "2nd", primaryTitle: "2nd", primaryRole: .input(.toggleSecond), row: 0, column: 0, style: .accent, fontSize: 24),
            CalculatorKeySpec(id: "(", primaryTitle: "(", primaryRole: .input(.leftParen), row: 0, column: 1, style: .topFunction, fontSize: 28),
            CalculatorKeySpec(id: ")", primaryTitle: ")", primaryRole: .input(.rightParen), row: 0, column: 2, style: .topFunction, fontSize: 28),
            CalculatorKeySpec(id: "percent", primaryTitle: "%", primaryRole: .input(.percent), row: 0, column: 3, style: .topFunction, fontSize: 24),
            CalculatorKeySpec(id: "mc2", primaryTitle: "mc", primaryRole: .input(.memoryClear), row: 0, column: 4, style: .topFunction, fontSize: 20),
            CalculatorKeySpec(id: "m+2", primaryTitle: "m+", primaryRole: .input(.memoryAdd), row: 0, column: 5, style: .topFunction, fontSize: 20),
            CalculatorKeySpec(id: "m-2", primaryTitle: "m-", primaryRole: .input(.memorySubtract), row: 0, column: 6, style: .topFunction, fontSize: 20),
            CalculatorKeySpec(id: "mr2", primaryTitle: "mr", primaryRole: .input(.memoryRecall), row: 0, column: 7, style: .topFunction, fontSize: 20),

            CalculatorKeySpec(id: "reciprocal", primaryTitle: "1/x", primaryRole: .input(.unary(.reciprocal)), row: 1, column: 0, style: .topFunction, fontSize: 23),
            CalculatorKeySpec(id: "square", primaryTitle: "x²", secondaryTitle: "√", primaryRole: .input(.unary(.square)), secondaryRole: .input(.unary(.sqrt)), row: 1, column: 1, style: .topFunction, fontSize: 24),
            CalculatorKeySpec(id: "cube", primaryTitle: "x³", secondaryTitle: "∛x", primaryRole: .input(.unary(.cube)), secondaryRole: .input(.unary(.cbrt)), row: 1, column: 2, style: .topFunction, fontSize: 23),
            CalculatorKeySpec(id: "power", primaryTitle: "yˣ", secondaryTitle: "x√y", primaryRole: .input(.binary(.power)), secondaryRole: .input(.binary(.root)), row: 1, column: 3, style: .topFunction, fontSize: 24),
            CalculatorKeySpec(id: "clear2", primaryTitle: "AC", primaryRole: .clearDynamic, row: 1, column: 4, style: .midFunction, fontSize: 24),
            CalculatorKeySpec(id: "sign2", primaryTitle: "+/-", primaryRole: .input(.toggleSign), row: 1, column: 5, style: .midFunction, fontSize: 24),
            CalculatorKeySpec(id: "divide2", primaryTitle: "÷", primaryRole: .input(.binary(.divide)), row: 1, column: 6, style: .operatorKey, fontSize: 30),
            CalculatorKeySpec(id: "multiply2", primaryTitle: "×", primaryRole: .input(.binary(.multiply)), row: 1, column: 7, style: .operatorKey, fontSize: 30),

            CalculatorKeySpec(id: "factorial", primaryTitle: "x!", primaryRole: .input(.unary(.factorial)), row: 2, column: 0, style: .topFunction, fontSize: 24),
            CalculatorKeySpec(id: "sqrt", primaryTitle: "√", secondaryTitle: "x²", primaryRole: .input(.unary(.sqrt)), secondaryRole: .input(.unary(.square)), row: 2, column: 1, style: .topFunction, fontSize: 26),
            CalculatorKeySpec(id: "root", primaryTitle: "x√y", secondaryTitle: "yˣ", primaryRole: .input(.binary(.root)), secondaryRole: .input(.binary(.power)), row: 2, column: 2, style: .topFunction, fontSize: 22),
            CalculatorKeySpec(id: "log", primaryTitle: "log", secondaryTitle: "10ˣ", primaryRole: .input(.unary(.log10)), secondaryRole: .input(.unary(.tenPower)), row: 2, column: 3, style: .topFunction, fontSize: 22),
            CalculatorKeySpec(id: "7s", primaryTitle: "7", primaryRole: .input(.digit(7)), row: 2, column: 4, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "8s", primaryTitle: "8", primaryRole: .input(.digit(8)), row: 2, column: 5, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "9s", primaryTitle: "9", primaryRole: .input(.digit(9)), row: 2, column: 6, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "minus2", primaryTitle: "−", primaryRole: .input(.binary(.subtract)), row: 2, column: 7, style: .operatorKey, fontSize: 30),

            CalculatorKeySpec(id: "sin", primaryTitle: "sin", secondaryTitle: "sin⁻¹", primaryRole: .input(.unary(.sine)), secondaryRole: .input(.unary(.inverseSine)), row: 3, column: 0, style: .topFunction, fontSize: 22),
            CalculatorKeySpec(id: "cos", primaryTitle: "cos", secondaryTitle: "cos⁻¹", primaryRole: .input(.unary(.cosine)), secondaryRole: .input(.unary(.inverseCosine)), row: 3, column: 1, style: .topFunction, fontSize: 22),
            CalculatorKeySpec(id: "tan", primaryTitle: "tan", secondaryTitle: "tan⁻¹", primaryRole: .input(.unary(.tangent)), secondaryRole: .input(.unary(.inverseTangent)), row: 3, column: 2, style: .topFunction, fontSize: 22),
            CalculatorKeySpec(id: "ln", primaryTitle: "ln", secondaryTitle: "eˣ", primaryRole: .input(.unary(.naturalLog)), secondaryRole: .input(.unary(.expE)), row: 3, column: 3, style: .topFunction, fontSize: 24),
            CalculatorKeySpec(id: "4s", primaryTitle: "4", primaryRole: .input(.digit(4)), row: 3, column: 4, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "5s", primaryTitle: "5", primaryRole: .input(.digit(5)), row: 3, column: 5, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "6s", primaryTitle: "6", primaryRole: .input(.digit(6)), row: 3, column: 6, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "plus2", primaryTitle: "+", primaryRole: .input(.binary(.add)), row: 3, column: 7, style: .operatorKey, fontSize: 30),

            CalculatorKeySpec(id: "sinh", primaryTitle: "sinh", secondaryTitle: "sinh⁻¹", primaryRole: .input(.unary(.hyperbolicSine)), secondaryRole: .input(.unary(.inverseHyperbolicSine)), row: 4, column: 0, style: .topFunction, fontSize: 20),
            CalculatorKeySpec(id: "cosh", primaryTitle: "cosh", secondaryTitle: "cosh⁻¹", primaryRole: .input(.unary(.hyperbolicCosine)), secondaryRole: .input(.unary(.inverseHyperbolicCosine)), row: 4, column: 1, style: .topFunction, fontSize: 20),
            CalculatorKeySpec(id: "tanh", primaryTitle: "tanh", secondaryTitle: "tanh⁻¹", primaryRole: .input(.unary(.hyperbolicTangent)), secondaryRole: .input(.unary(.inverseHyperbolicTangent)), row: 4, column: 2, style: .topFunction, fontSize: 20),
            CalculatorKeySpec(id: "exp", primaryTitle: "eˣ", secondaryTitle: "ln", primaryRole: .input(.unary(.expE)), secondaryRole: .input(.unary(.naturalLog)), row: 4, column: 3, style: .topFunction, fontSize: 24),
            CalculatorKeySpec(id: "1s", primaryTitle: "1", primaryRole: .input(.digit(1)), row: 4, column: 4, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "2s", primaryTitle: "2", primaryRole: .input(.digit(2)), row: 4, column: 5, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "3s", primaryTitle: "3", primaryRole: .input(.digit(3)), row: 4, column: 6, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "equals2", primaryTitle: "=", primaryRole: .input(.equals), row: 4, column: 7, rowSpan: 2, style: .equals, fontSize: 36),

            CalculatorKeySpec(id: "angle", primaryTitle: "Deg", primaryRole: .angleDynamic, row: 5, column: 0, style: .topFunction, fontSize: 22),
            CalculatorKeySpec(id: "pi", primaryTitle: "π", primaryRole: .input(.constantPi), row: 5, column: 1, style: .topFunction, fontSize: 28),
            CalculatorKeySpec(id: "ee", primaryTitle: "EE", primaryRole: .input(.ee), row: 5, column: 2, style: .topFunction, fontSize: 22),
            CalculatorKeySpec(id: "rand", primaryTitle: "Rand", primaryRole: .input(.random), row: 5, column: 3, style: .topFunction, fontSize: 20),
            CalculatorKeySpec(id: "0s", primaryTitle: "0", primaryRole: .input(.digit(0)), row: 5, column: 4, columnSpan: 2, style: .number, fontSize: 30),
            CalculatorKeySpec(id: "dot2", primaryTitle: ".", primaryRole: .input(.decimalPoint), row: 5, column: 6, style: .number, fontSize: 34)
        ]
    }
}

private struct ScientificCanvasView: View {
    let displayText: String
    let angleBadge: String
    let keys: [CalculatorKeySpec]
    let useSecondary: Bool
    let clearTitle: String
    let angleToggleTitle: String
    let secondIsActive: Bool
    let onTap: (CalculatorKeyRole) -> Void

    var body: some View {
        VStack(spacing: 0) {
            status_bar()
                .frame(minHeight: 24, maxHeight: 24)

            CalculatorDisplayView(
                text: displayText,
                angleBadge: angleBadge,
                scientific: true
            )
            .frame(height: 96)

            CalculatorKeyGrid(
                rows: 6,
                columns: 8,
                spacing: 5,
                keys: keys,
                useSecondary: useSecondary,
                clearTitle: clearTitle,
                angleToggleTitle: angleToggleTitle,
                onTap: onTap,
                secondIsActive: secondIsActive
            )
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .background(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 43/255, green: 44/255, blue: 46/255), location: 0),
                    .init(color: Color(red: 25/255, green: 25/255, blue: 27/255), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(.rect(cornerRadius: 4))
    }
}

private struct CalculatorDisplayView: View {
    let text: String
    let angleBadge: String?
    let scientific: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: scientific ? 0 : 2)
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(red: 244/255, green: 246/255, blue: 234/255), location: 0),
                            .init(color: Color(red: 238/255, green: 241/255, blue: 229/255), location: 0.6),
                            .init(color: Color(red: 232/255, green: 236/255, blue: 223/255), location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: scientific ? 0 : 2)
                        .stroke(Color.black.opacity(0.35), lineWidth: 0.8)
                )

            if let angleBadge {
                Text(angleBadge)
                    .font(.custom("Helvetica Neue Medium", fixedSize: 30/2))
                    .foregroundColor(Color.black.opacity(0.8))
                    .padding(.leading, 8)
                    .padding(.bottom, 7)
            }

            HStack {
                Spacer()
                Text(text)
                    .font(.custom(scientific ? "Helvetica Neue Light" : "Helvetica Neue Bold", fixedSize: scientific ? 62/2 : 72))
                    .foregroundColor(Color(red: 5/255, green: 54/255, blue: 41/255))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, scientific ? 0 : 0)
    }
}

private struct CalculatorKeyGrid: View {
    let rows: Int
    let columns: Int
    let spacing: CGFloat
    let keys: [CalculatorKeySpec]
    let useSecondary: Bool
    let clearTitle: String
    let angleToggleTitle: String
    let onTap: (CalculatorKeyRole) -> Void
    let secondIsActive: Bool
    var compactRows: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = (geometry.size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)

            // In compact mode, cap cell height and redistribute extra space as row gaps
            let uniformCellHeight = (geometry.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
            let maxCellHeight = cellWidth * 0.85
            let useCompact = compactRows && uniformCellHeight > maxCellHeight
            let cellHeight = useCompact ? maxCellHeight : uniformCellHeight
            let effectiveSpacing = useCompact
                ? (geometry.size.height - cellHeight * CGFloat(rows)) / CGFloat(rows - 1)
                : spacing

            ZStack(alignment: .topLeading) {
                ForEach(keys) { key in
                    let width = cellWidth * CGFloat(key.columnSpan) + spacing * CGFloat(key.columnSpan - 1)
                    let height = cellHeight * CGFloat(key.rowSpan) + effectiveSpacing * CGFloat(key.rowSpan - 1)

                    CalculatorKeyButton(
                        title: key.resolvedTitle(
                            useSecondary: useSecondary,
                            clearTitle: clearTitle,
                            angleToggleTitle: angleToggleTitle
                        ),
                        style: key.style,
                        fontSize: key.fontSize,
                        isSecondKeyActive: key.id == "2nd" && secondIsActive,
                        action: {
                            onTap(key.resolvedRole(useSecondary: useSecondary))
                        }
                    )
                    .frame(width: width, height: height)
                    .offset(
                        x: CGFloat(key.column) * (cellWidth + spacing),
                        y: CGFloat(key.row) * (cellHeight + effectiveSpacing)
                    )
                }
            }
        }
    }
}

private struct CalculatorKeyButton: View {
    let title: String
    let style: CalculatorKeyVisualStyle
    let fontSize: CGFloat
    let isSecondKeyActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderColor, lineWidth: 0.75)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.24))
                            .frame(height: 8)
                            .offset(y: -12)
                            .blur(radius: 0.8)
                            .clipped()
                    )

                Text(title)
                    .font(.custom("Helvetica Neue Bold", fixedSize: fontSize))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 2)
                    .shadow(color: textShadowColor, radius: 0, x: 0, y: textShadowYOffset)
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundGradient: LinearGradient {
        if isSecondKeyActive {
            return LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 169/255, green: 180/255, blue: 206/255), location: 0),
                    .init(color: Color(red: 87/255, green: 113/255, blue: 166/255), location: 0.5),
                    .init(color: Color(red: 58/255, green: 84/255, blue: 140/255), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }

        switch style {
        case .topFunction:
            return LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 182/255, green: 191/255, blue: 203/255), location: 0),
                    .init(color: Color(red: 118/255, green: 126/255, blue: 139/255), location: 0.52),
                    .init(color: Color(red: 81/255, green: 88/255, blue: 96/255), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        case .midFunction, .operatorKey:
            return LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 176/255, green: 155/255, blue: 140/255), location: 0),
                    .init(color: Color(red: 103/255, green: 85/255, blue: 72/255), location: 0.52),
                    .init(color: Color(red: 70/255, green: 56/255, blue: 47/255), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        case .number:
            return LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 114/255, green: 114/255, blue: 116/255), location: 0),
                    .init(color: Color(red: 26/255, green: 26/255, blue: 27/255), location: 0.48),
                    .init(color: Color.black, location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        case .equals:
            return LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 1, green: 183/255, blue: 77/255), location: 0),
                    .init(color: Color(red: 1, green: 150/255, blue: 22/255), location: 0.5),
                    .init(color: Color(red: 252/255, green: 134/255, blue: 0), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        case .accent:
            return LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(red: 160/255, green: 174/255, blue: 201/255), location: 0),
                    .init(color: Color(red: 98/255, green: 110/255, blue: 138/255), location: 0.5),
                    .init(color: Color(red: 70/255, green: 79/255, blue: 102/255), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var borderColor: Color {
        switch style {
        case .equals:
            return Color(red: 110/255, green: 58/255, blue: 0)
        default:
            return Color.black.opacity(0.65)
        }
    }

    private var textColor: Color {
        switch style {
        case .number, .equals, .accent:
            return .white
        default:
            return .white
        }
    }

    private var textShadowColor: Color {
        switch style {
        case .number, .equals:
            return Color.black.opacity(0.92)
        default:
            return Color.black.opacity(0.72)
        }
    }

    private var textShadowYOffset: CGFloat {
        switch style {
        case .number, .equals:
            return -0.75
        default:
            return -0.6
        }
    }
}

#Preview {
    Calculator()
        .frame(width: 390, height: 760)
        .background(Color.black)
}

