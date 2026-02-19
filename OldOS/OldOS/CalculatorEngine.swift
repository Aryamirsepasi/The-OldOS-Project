import Foundation

public enum AngleUnit: String, CaseIterable, Equatable, Hashable {
    case radians = "Rad"
    case degrees = "Deg"

    mutating func toggle() {
        self = (self == .radians) ? .degrees : .radians
    }
}

public enum BinaryOperator: String, CaseIterable, Equatable, Hashable {
    case add = "+"
    case subtract = "-"
    case multiply = "×"
    case divide = "÷"
    case power = "yˣ"
    case root = "x√y"

    var precedence: Int {
        switch self {
        case .add, .subtract:
            return 1
        case .multiply, .divide:
            return 2
        case .power, .root:
            return 3
        }
    }

    var isRightAssociative: Bool {
        switch self {
        case .power, .root:
            return true
        default:
            return false
        }
    }
}

public enum UnaryOperator: String, CaseIterable, Equatable, Hashable {
    case reciprocal = "1/x"
    case square = "x²"
    case cube = "x³"
    case sqrt = "√"
    case cbrt = "∛x"
    case factorial = "x!"
    case tenPower = "10ˣ"
    case expE = "eˣ"
    case naturalLog = "ln"
    case log10 = "log"

    case sine = "sin"
    case cosine = "cos"
    case tangent = "tan"
    case inverseSine = "sin⁻¹"
    case inverseCosine = "cos⁻¹"
    case inverseTangent = "tan⁻¹"

    case hyperbolicSine = "sinh"
    case hyperbolicCosine = "cosh"
    case hyperbolicTangent = "tanh"
    case inverseHyperbolicSine = "sinh⁻¹"
    case inverseHyperbolicCosine = "cosh⁻¹"
    case inverseHyperbolicTangent = "tanh⁻¹"

    case twoPower = "2ˣ"
    case negate = "+/-"
    case percent = "%"
}

public enum ScientificToken: Equatable, Hashable {
    case number(Double)
    case binary(BinaryOperator)
    case unary(UnaryOperator)
    case leftParen
    case rightParen
}

public enum CalculatorInput: Equatable, Hashable {
    case digit(Int)
    case decimalPoint
    case toggleSign
    case percent
    case binary(BinaryOperator)
    case unary(UnaryOperator)
    case equals

    case clearEntry
    case allClear

    case memoryClear
    case memoryAdd
    case memorySubtract
    case memoryRecall

    case leftParen
    case rightParen
    case constantPi
    case random
    case ee

    case toggleSecond
    case toggleAngleUnit
    case setAngleUnit(AngleUnit)
}

public struct CalculatorState: Equatable {
    public var displayText: String = "0"
    public var memoryValue: Double = 0
    public var hasMemoryValue: Bool = false
    public var angleUnit: AngleUnit = .radians
    public var isSecondActive: Bool = false
    public var isScientificMode: Bool = false
    public var scientificTokens: [ScientificToken] = []
    public var canUseClearEntry: Bool = false

    public init() {}
}

private enum CalculatorEngineError: Error {
    case divideByZero
    case invalidDomain
    case malformedExpression
}

public struct CalculatorEngine {
    public private(set) var state = CalculatorState()

    private var entryText: String = "0"
    private var isEnteringNumber = false
    private var justEvaluated = false
    private var errorState = false
    private var currentValue: Double = 0

    private var portraitAccumulator: Double?
    private var portraitPendingOperator: BinaryOperator?
    private var portraitRepeatOperand: Double?
    private var portraitRepeatOperator: BinaryOperator?

    private var scientificTokens: [ScientificToken] = []
    private var scientificOpenParens = 0

    public init() {}

    public mutating func setScientificMode(_ enabled: Bool) {
        guard state.isScientificMode != enabled else { return }

        if enabled {
            state.isScientificMode = true
            scientificTokens = [.number(currentValue)]
            scientificOpenParens = 0
            state.scientificTokens = scientificTokens
            isEnteringNumber = false
            justEvaluated = true
        } else {
            state.isScientificMode = false
            scientificTokens.removeAll()
            scientificOpenParens = 0
            state.scientificTokens = []

            portraitAccumulator = nil
            portraitPendingOperator = nil
            portraitRepeatOperand = nil
            portraitRepeatOperator = nil

            entryText = rawNumberString(from: currentValue)
            isEnteringNumber = false
            justEvaluated = true
        }

        refreshDisplay()
    }

    public mutating func apply(_ input: CalculatorInput) {
        if errorState {
            switch input {
            case .allClear:
                resetAll(keepMemory: true)
            case .clearEntry:
                clearErrorToZero()
            case .digit, .decimalPoint, .constantPi, .random, .memoryRecall:
                clearErrorToZero()
            default:
                return
            }
        }

        switch input {
        case .digit(let digit):
            handleDigit(digit)
        case .decimalPoint:
            handleDecimalPoint()
        case .toggleSign:
            handleSignToggle()
        case .percent:
            handlePercent()
        case .binary(let op):
            handleBinary(op)
        case .unary(let op):
            handleUnary(op)
        case .equals:
            handleEquals()

        case .clearEntry:
            handleClearEntry()
        case .allClear:
            resetAll(keepMemory: true)

        case .memoryClear:
            state.memoryValue = 0
            state.hasMemoryValue = false
        case .memoryAdd:
            state.memoryValue += resolvedCurrentValue()
            state.hasMemoryValue = true
        case .memorySubtract:
            state.memoryValue -= resolvedCurrentValue()
            state.hasMemoryValue = true
        case .memoryRecall:
            handleMemoryRecall()

        case .leftParen:
            handleLeftParen()
        case .rightParen:
            handleRightParen()
        case .constantPi:
            handleConstant(Double.pi)
        case .random:
            handleConstant(Double.random(in: 0..<1))
        case .ee:
            handleEE()

        case .toggleSecond:
            state.isSecondActive.toggle()
        case .toggleAngleUnit:
            state.angleUnit.toggle()
        case .setAngleUnit(let unit):
            state.angleUnit = unit
        }

        refreshDisplay()
    }

    private mutating func handleDigit(_ digit: Int) {
        guard (0...9).contains(digit) else { return }

        if justEvaluated && portraitPendingOperator == nil && !state.isScientificMode {
            portraitAccumulator = nil
            portraitRepeatOperand = nil
            portraitRepeatOperator = nil
        }

        if !isEnteringNumber || justEvaluated {
            entryText = String(digit)
            isEnteringNumber = true
            justEvaluated = false
            return
        }

        if entryText.lowercased().contains("e") {
            entryText.append(String(digit))
            return
        }

        if entryText == "0" {
            entryText = String(digit)
            return
        }

        if entryText == "-0" {
            entryText = "-\(digit)"
            return
        }

        entryText.append(String(digit))
    }

    private mutating func handleDecimalPoint() {
        if justEvaluated && portraitPendingOperator == nil && !state.isScientificMode {
            portraitAccumulator = nil
            portraitRepeatOperand = nil
            portraitRepeatOperator = nil
        }

        let lower = entryText.lowercased()
        if lower.contains("e") {
            return
        }

        if !isEnteringNumber || justEvaluated {
            entryText = "0."
            isEnteringNumber = true
            justEvaluated = false
            return
        }

        if !entryText.contains(".") {
            entryText.append(".")
        }
    }

    private mutating func handleSignToggle() {
        if state.isScientificMode {
            if isEnteringNumber {
                toggleSignInEntry()
            } else {
                applyUnaryToCurrent(.negate, keepAsEntry: false)
            }
        } else {
            if isEnteringNumber {
                toggleSignInEntry()
            } else {
                applyUnaryToCurrent(.negate, keepAsEntry: portraitPendingOperator != nil)
            }
        }
    }

    private mutating func toggleSignInEntry() {
        let lower = entryText.lowercased()
        if let eIndex = lower.firstIndex(of: "e") {
            let afterE = entryText.index(after: eIndex)
            if afterE < entryText.endIndex {
                if entryText[afterE] == "+" {
                    entryText.remove(at: afterE)
                    entryText.insert("-", at: afterE)
                } else if entryText[afterE] == "-" {
                    entryText.remove(at: afterE)
                    entryText.insert("+", at: afterE)
                } else {
                    entryText.insert("-", at: afterE)
                }
            } else {
                entryText.append("-")
            }
            return
        }

        if entryText.hasPrefix("-") {
            entryText.removeFirst()
            if entryText.isEmpty { entryText = "0" }
        } else {
            entryText = "-" + entryText
        }
    }

    private mutating func handlePercent() {
        if state.isScientificMode {
            applyUnaryToCurrent(.percent, keepAsEntry: true)
            return
        }

        if let accumulator = portraitAccumulator, portraitPendingOperator != nil {
            let percentValue = accumulator * parsedEntryValue() / 100
            setEntry(from: percentValue, keepAsEntry: true)
            return
        }

        applyUnaryToCurrent(.percent, keepAsEntry: true)
    }

    private mutating func handleBinary(_ op: BinaryOperator) {
        if state.isScientificMode {
            handleScientificBinary(op)
            return
        }

        let operand = resolvedCurrentValue()

        if portraitAccumulator == nil {
            portraitAccumulator = operand
        } else if let pending = portraitPendingOperator, isEnteringNumber {
            do {
                portraitAccumulator = try applyBinary(pending, portraitAccumulator ?? 0, operand)
            } catch {
                setError()
                return
            }
        }

        portraitPendingOperator = op
        portraitRepeatOperand = nil
        portraitRepeatOperator = nil
        isEnteringNumber = false
        justEvaluated = false

        if let accumulator = portraitAccumulator {
            setEntry(from: accumulator, keepAsEntry: false)
        }
    }

    private mutating func handleScientificBinary(_ op: BinaryOperator) {
        if isEnteringNumber {
            commitScientificEntry()
        }

        if scientificTokens.isEmpty {
            scientificTokens = [.number(currentValue)]
        }

        if case .binary = scientificTokens.last {
            scientificTokens.removeLast()
        }

        scientificTokens.append(.binary(op))
        state.scientificTokens = scientificTokens
        justEvaluated = false
    }

    private mutating func handleEquals() {
        if state.isScientificMode {
            handleScientificEquals()
            return
        }

        if let pending = portraitPendingOperator {
            let lhs = portraitAccumulator ?? currentValue
            let rhs: Double
            if isEnteringNumber {
                rhs = parsedEntryValue()
                portraitRepeatOperand = rhs
            } else if let repeatOperand = portraitRepeatOperand {
                rhs = repeatOperand
            } else {
                rhs = lhs
                portraitRepeatOperand = rhs
            }

            do {
                let result = try applyBinary(pending, lhs, rhs)
                portraitAccumulator = result
                portraitRepeatOperator = pending
                portraitPendingOperator = nil
                setEntry(from: result, keepAsEntry: false)
                isEnteringNumber = false
                justEvaluated = true
            } catch {
                setError()
            }
            return
        }

        if let repeatOperator = portraitRepeatOperator, let repeatOperand = portraitRepeatOperand {
            do {
                let result = try applyBinary(repeatOperator, resolvedCurrentValue(), repeatOperand)
                portraitAccumulator = result
                setEntry(from: result, keepAsEntry: false)
                isEnteringNumber = false
                justEvaluated = true
            } catch {
                setError()
            }
        }
    }

    private mutating func handleScientificEquals() {
        if isEnteringNumber {
            commitScientificEntry()
        }

        while scientificOpenParens > 0 {
            scientificTokens.append(.rightParen)
            scientificOpenParens -= 1
        }

        if scientificTokens.isEmpty {
            scientificTokens = [.number(resolvedCurrentValue())]
        }

        if case .binary = scientificTokens.last {
            scientificTokens.removeLast()
        }

        do {
            let result = try evaluateScientificTokens(scientificTokens)
            scientificTokens = [.number(result)]
            state.scientificTokens = scientificTokens
            setEntry(from: result, keepAsEntry: false)
            isEnteringNumber = false
            justEvaluated = true
        } catch {
            setError()
        }
    }

    private mutating func handleUnary(_ op: UnaryOperator) {
        applyUnaryToCurrent(op, keepAsEntry: state.isScientificMode || portraitPendingOperator != nil)
    }

    private mutating func applyUnaryToCurrent(_ op: UnaryOperator, keepAsEntry: Bool) {
        do {
            let result = try applyUnary(op, to: resolvedCurrentValue(), angleUnit: state.angleUnit)

            if state.isScientificMode {
                if isEnteringNumber {
                    setEntry(from: result, keepAsEntry: true)
                } else {
                    replaceLastScientificNumber(with: result)
                    setEntry(from: result, keepAsEntry: false)
                }
            } else {
                setEntry(from: result, keepAsEntry: keepAsEntry)
            }

            if keepAsEntry {
                isEnteringNumber = true
                justEvaluated = false
            } else {
                isEnteringNumber = false
                justEvaluated = true
            }
        } catch {
            setError()
        }
    }

    private mutating func handleClearEntry() {
        if errorState {
            clearErrorToZero()
            return
        }

        entryText = "0"
        isEnteringNumber = false
        justEvaluated = false
        currentValue = 0

        if state.isScientificMode {
            if case .number = scientificTokens.last {
                scientificTokens.removeLast()
            }
            state.scientificTokens = scientificTokens
        }
    }

    private mutating func handleMemoryRecall() {
        guard state.hasMemoryValue else { return }
        setEntry(from: state.memoryValue, keepAsEntry: true)
        isEnteringNumber = true
        justEvaluated = false

        if state.isScientificMode {
            if case .number = scientificTokens.last {
                scientificTokens.removeLast()
            }
        }
    }

    private mutating func handleLeftParen() {
        guard state.isScientificMode else { return }

        if isEnteringNumber {
            commitScientificEntry()
        }

        if let last = scientificTokens.last {
            switch last {
            case .number, .rightParen:
                scientificTokens.append(.binary(.multiply))
            default:
                break
            }
        }

        scientificTokens.append(.leftParen)
        scientificOpenParens += 1
        state.scientificTokens = scientificTokens
        isEnteringNumber = false
        justEvaluated = false
    }

    private mutating func handleRightParen() {
        guard state.isScientificMode else { return }
        guard scientificOpenParens > 0 else { return }

        if isEnteringNumber {
            commitScientificEntry()
        }

        if let last = scientificTokens.last {
            switch last {
            case .leftParen, .binary:
                return
            default:
                break
            }
        }

        scientificTokens.append(.rightParen)
        scientificOpenParens -= 1
        state.scientificTokens = scientificTokens
        isEnteringNumber = false
        justEvaluated = false
    }

    private mutating func handleConstant(_ value: Double) {
        setEntry(from: value, keepAsEntry: true)
        isEnteringNumber = true
        justEvaluated = false

        if state.isScientificMode, case .number = scientificTokens.last {
            scientificTokens.removeLast()
            state.scientificTokens = scientificTokens
        }
    }

    private mutating func handleEE() {
        guard state.isScientificMode else { return }

        if !isEnteringNumber {
            entryText = rawNumberString(from: resolvedCurrentValue())
            isEnteringNumber = true
        }

        if !entryText.lowercased().contains("e") {
            entryText.append("e")
        }

        justEvaluated = false
    }

    private mutating func commitScientificEntry() {
        let value = parsedEntryValue()
        scientificTokens.append(.number(value))
        state.scientificTokens = scientificTokens
        isEnteringNumber = false
        currentValue = value
    }

    private mutating func replaceLastScientificNumber(with value: Double) {
        if case .number = scientificTokens.last {
            scientificTokens.removeLast()
        }
        scientificTokens.append(.number(value))
        state.scientificTokens = scientificTokens
    }

    private func evaluateScientificTokens(_ tokens: [ScientificToken]) throws -> Double {
        let rpn = try toRPN(tokens)
        return try evaluateRPN(rpn)
    }

    private func toRPN(_ tokens: [ScientificToken]) throws -> [ScientificToken] {
        var output: [ScientificToken] = []
        var operators: [ScientificToken] = []

        for token in tokens {
            switch token {
            case .number:
                output.append(token)
            case .unary(let unary):
                while let top = operators.last {
                    switch top {
                    case .unary:
                        output.append(operators.removeLast())
                    case .binary(let other):
                        if other.precedence >= 4 {
                            output.append(operators.removeLast())
                        } else {
                            break
                        }
                    default:
                        break
                    }
                    if case .leftParen = operators.last { break }
                }
                operators.append(.unary(unary))
            case .binary(let op):
                while let top = operators.last {
                    switch top {
                    case .binary(let other):
                        let shouldPop: Bool
                        if op.isRightAssociative {
                            shouldPop = other.precedence > op.precedence
                        } else {
                            shouldPop = other.precedence >= op.precedence
                        }
                        if shouldPop {
                            output.append(operators.removeLast())
                        } else {
                            break
                        }
                    case .unary:
                        output.append(operators.removeLast())
                    case .leftParen:
                        break
                    default:
                        break
                    }
                    if case .leftParen = operators.last { break }
                }
                operators.append(.binary(op))
            case .leftParen:
                operators.append(.leftParen)
            case .rightParen:
                var foundLeft = false
                while let top = operators.last {
                    operators.removeLast()
                    if case .leftParen = top {
                        foundLeft = true
                        break
                    }
                    output.append(top)
                }
                if !foundLeft {
                    throw CalculatorEngineError.malformedExpression
                }
            }
        }

        while let top = operators.last {
            operators.removeLast()
            if case .leftParen = top {
                throw CalculatorEngineError.malformedExpression
            }
            output.append(top)
        }

        return output
    }

    private func evaluateRPN(_ tokens: [ScientificToken]) throws -> Double {
        var stack: [Double] = []

        for token in tokens {
            switch token {
            case .number(let value):
                stack.append(value)
            case .binary(let op):
                guard let rhs = stack.popLast(), let lhs = stack.popLast() else {
                    throw CalculatorEngineError.malformedExpression
                }
                stack.append(try applyBinary(op, lhs, rhs))
            case .unary(let op):
                guard let value = stack.popLast() else {
                    throw CalculatorEngineError.malformedExpression
                }
                stack.append(try applyUnary(op, to: value, angleUnit: state.angleUnit))
            case .leftParen, .rightParen:
                throw CalculatorEngineError.malformedExpression
            }
        }

        guard stack.count == 1, let result = stack.first else {
            throw CalculatorEngineError.malformedExpression
        }

        return result
    }

    private func applyBinary(_ op: BinaryOperator, _ lhs: Double, _ rhs: Double) throws -> Double {
        switch op {
        case .add:
            return lhs + rhs
        case .subtract:
            return lhs - rhs
        case .multiply:
            return lhs * rhs
        case .divide:
            if abs(rhs) <= .ulpOfOne {
                throw CalculatorEngineError.divideByZero
            }
            return lhs / rhs
        case .power:
            return pow(lhs, rhs)
        case .root:
            if abs(lhs) <= .ulpOfOne {
                throw CalculatorEngineError.divideByZero
            }
            if rhs < 0 && truncatingRemainderSafe(lhs, 2) == 0 {
                throw CalculatorEngineError.invalidDomain
            }
            return pow(rhs, 1 / lhs)
        }
    }

    private func applyUnary(_ op: UnaryOperator, to value: Double, angleUnit: AngleUnit) throws -> Double {
        switch op {
        case .reciprocal:
            if abs(value) <= .ulpOfOne { throw CalculatorEngineError.divideByZero }
            return 1 / value
        case .square:
            return value * value
        case .cube:
            return value * value * value
        case .sqrt:
            if value < 0 { throw CalculatorEngineError.invalidDomain }
            return Foundation.sqrt(value)
        case .cbrt:
            return pow(value, 1 / 3)
        case .factorial:
            if value < 0 || value.rounded() != value { throw CalculatorEngineError.invalidDomain }
            if value > 170 { throw CalculatorEngineError.invalidDomain }
            return factorial(Int(value))
        case .tenPower:
            return pow(10, value)
        case .expE:
            return Foundation.exp(value)
        case .naturalLog:
            if value <= 0 { throw CalculatorEngineError.invalidDomain }
            return Foundation.log(value)
        case .log10:
            if value <= 0 { throw CalculatorEngineError.invalidDomain }
            return Foundation.log10(value)
        case .sine:
            return Foundation.sin(angleToRadians(value, unit: angleUnit))
        case .cosine:
            return Foundation.cos(angleToRadians(value, unit: angleUnit))
        case .tangent:
            return Foundation.tan(angleToRadians(value, unit: angleUnit))
        case .inverseSine:
            if value < -1 || value > 1 { throw CalculatorEngineError.invalidDomain }
            return radiansToAngle(Foundation.asin(value), unit: angleUnit)
        case .inverseCosine:
            if value < -1 || value > 1 { throw CalculatorEngineError.invalidDomain }
            return radiansToAngle(Foundation.acos(value), unit: angleUnit)
        case .inverseTangent:
            return radiansToAngle(Foundation.atan(value), unit: angleUnit)
        case .hyperbolicSine:
            return Foundation.sinh(value)
        case .hyperbolicCosine:
            return Foundation.cosh(value)
        case .hyperbolicTangent:
            return Foundation.tanh(value)
        case .inverseHyperbolicSine:
            return Foundation.asinh(value)
        case .inverseHyperbolicCosine:
            if value < 1 { throw CalculatorEngineError.invalidDomain }
            return Foundation.acosh(value)
        case .inverseHyperbolicTangent:
            if abs(value) >= 1 { throw CalculatorEngineError.invalidDomain }
            return Foundation.atanh(value)
        case .twoPower:
            return pow(2, value)
        case .negate:
            return -value
        case .percent:
            return value / 100
        }
    }

    private mutating func setEntry(from value: Double, keepAsEntry: Bool) {
        currentValue = normalizedZero(value)
        entryText = rawNumberString(from: currentValue)
        if keepAsEntry {
            isEnteringNumber = true
        }
    }

    private func resolvedCurrentValue() -> Double {
        if isEnteringNumber {
            return parsedEntryValue()
        }
        return currentValue
    }

    private func parsedEntryValue() -> Double {
        var candidate = entryText
        if candidate.isEmpty || candidate == "-" || candidate == "+" {
            return currentValue
        }

        if candidate.hasSuffix(".") {
            candidate.removeLast()
        }

        if candidate.isEmpty || candidate == "-" || candidate == "+" {
            return 0
        }

        let lower = candidate.lowercased()
        if lower.hasSuffix("e") || lower.hasSuffix("e+") || lower.hasSuffix("e-") {
            candidate.append("0")
        }

        return Double(candidate) ?? currentValue
    }

    private mutating func refreshDisplay() {
        state.scientificTokens = scientificTokens
        state.canUseClearEntry = isEnteringNumber || errorState || entryText != "0" || portraitPendingOperator != nil

        if errorState {
            state.displayText = "Error"
            return
        }

        if isEnteringNumber {
            state.displayText = formattedRawEntry(entryText)
            currentValue = parsedEntryValue()
            return
        }

        state.displayText = formattedNumber(currentValue, scientificIfNeeded: true)
    }

    private mutating func clearErrorToZero() {
        errorState = false
        entryText = "0"
        currentValue = 0
        isEnteringNumber = false
        justEvaluated = false

        if state.isScientificMode {
            scientificTokens = [.number(0)]
            scientificOpenParens = 0
            state.scientificTokens = scientificTokens
        }
    }

    private mutating func setError() {
        errorState = true
        isEnteringNumber = false
        justEvaluated = false
        portraitPendingOperator = nil
        portraitAccumulator = nil
        portraitRepeatOperand = nil
        portraitRepeatOperator = nil
        scientificTokens.removeAll()
        scientificOpenParens = 0
        state.scientificTokens = []
        state.displayText = "Error"
    }

    private mutating func resetAll(keepMemory: Bool) {
        let memoryValue = state.memoryValue
        let hasMemory = state.hasMemoryValue
        let angle = state.angleUnit
        let second = state.isSecondActive
        let scientific = state.isScientificMode

        state = CalculatorState()
        state.angleUnit = angle
        state.isSecondActive = second
        state.isScientificMode = scientific

        if keepMemory {
            state.memoryValue = memoryValue
            state.hasMemoryValue = hasMemory
        }

        entryText = "0"
        isEnteringNumber = false
        justEvaluated = false
        errorState = false
        currentValue = 0

        portraitAccumulator = nil
        portraitPendingOperator = nil
        portraitRepeatOperand = nil
        portraitRepeatOperator = nil

        scientificTokens = scientific ? [.number(0)] : []
        scientificOpenParens = 0
        state.scientificTokens = scientificTokens
        refreshDisplay()
    }

    private func rawNumberString(from value: Double) -> String {
        let normalized = normalizedZero(value)

        if normalized == 0 {
            return "0"
        }

        let absValue = abs(normalized)
        if absValue >= 1e14 || absValue < 1e-12 {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = .scientific
            formatter.exponentSymbol = "e"
            formatter.usesGroupingSeparator = false
            formatter.maximumFractionDigits = 12
            return (formatter.string(from: NSNumber(value: normalized)) ?? "0").lowercased()
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 12
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: normalized)) ?? "0"
    }

    private func formattedNumber(_ value: Double, scientificIfNeeded: Bool) -> String {
        let normalized = normalizedZero(value)
        let absValue = abs(normalized)

        if scientificIfNeeded && absValue > 0 && (absValue >= 1e12 || absValue < 1e-10) {
            let scientific = NumberFormatter()
            scientific.locale = Locale(identifier: "en_US_POSIX")
            scientific.numberStyle = .scientific
            scientific.exponentSymbol = "e"
            scientific.maximumFractionDigits = 10
            scientific.minimumFractionDigits = 0
            return (scientific.string(from: NSNumber(value: normalized)) ?? "0").lowercased()
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: normalized)) ?? "0"
    }

    private func formattedRawEntry(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("e") {
            return raw.replacingOccurrences(of: "e", with: "E")
        }

        var value = raw
        var sign = ""

        if value.hasPrefix("-") {
            sign = "-"
            value.removeFirst()
        } else if value.hasPrefix("+") {
            value.removeFirst()
        }

        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let integerPart = parts.first.map(String.init) ?? "0"
        let fractionPart = parts.count > 1 ? String(parts[1]) : nil

        let groupedInteger = grouped(integerPart)

        if raw.hasSuffix(".") {
            return sign + groupedInteger + "."
        }

        if let fractionPart {
            return sign + groupedInteger + "." + fractionPart
        }

        return sign + groupedInteger
    }

    private func grouped(_ integer: String) -> String {
        guard !integer.isEmpty else { return "0" }
        var chars = Array(integer)
        var result: [Character] = []

        while chars.count > 3 {
            let suffix = chars.suffix(3)
            result.insert(contentsOf: suffix, at: 0)
            result.insert(",", at: 0)
            chars.removeLast(3)
        }

        result.insert(contentsOf: chars, at: 0)
        return String(result)
    }

    private func angleToRadians(_ value: Double, unit: AngleUnit) -> Double {
        switch unit {
        case .radians:
            return value
        case .degrees:
            return value * .pi / 180
        }
    }

    private func radiansToAngle(_ value: Double, unit: AngleUnit) -> Double {
        switch unit {
        case .radians:
            return value
        case .degrees:
            return value * 180 / .pi
        }
    }

    private func factorial(_ n: Int) -> Double {
        if n == 0 { return 1 }
        return (1...n).reduce(1) { $0 * Double($1) }
    }

    private func normalizedZero(_ value: Double) -> Double {
        if abs(value) <= 1e-14 {
            return 0
        }
        return value
    }

    private func truncatingRemainderSafe(_ lhs: Double, _ rhs: Double) -> Double {
        guard rhs != 0 else { return 0 }
        return lhs.truncatingRemainder(dividingBy: rhs)
    }
}
