import XCTest
@testable import OldOS

final class CalculatorEngineTests: XCTestCase {

    func testPortraitImmediateChaining() {
        var engine = CalculatorEngine()

        pressDigits("3", into: &engine)
        engine.apply(.binary(.add))
        pressDigits("4", into: &engine)
        engine.apply(.binary(.multiply))
        pressDigits("5", into: &engine)
        engine.apply(.equals)

        XCTAssertEqual(engine.state.displayText, "35")
    }

    func testBasicAddition() {
        var engine = CalculatorEngine()

        pressDigits("1", into: &engine)
        engine.apply(.binary(.add))
        pressDigits("2", into: &engine)
        engine.apply(.equals)

        XCTAssertEqual(engine.state.displayText, "3")
    }

    func testRepeatedEqualsRepeatsLastOperation() {
        var engine = CalculatorEngine()

        pressDigits("2", into: &engine)
        engine.apply(.binary(.add))
        pressDigits("3", into: &engine)
        engine.apply(.equals)
        engine.apply(.equals)

        XCTAssertEqual(engine.state.displayText, "8")
    }

    func testMemoryOperations() {
        var engine = CalculatorEngine()

        pressDigits("9", into: &engine)
        engine.apply(.memoryAdd)
        engine.apply(.allClear)
        engine.apply(.memoryRecall)

        XCTAssertEqual(engine.state.displayText, "9")

        engine.apply(.memorySubtract)
        engine.apply(.memoryRecall)

        XCTAssertEqual(engine.state.displayText, "0")

        engine.apply(.memoryClear)
        engine.apply(.allClear)
        engine.apply(.memoryRecall)

        XCTAssertEqual(engine.state.displayText, "0")
    }

    func testScientificParenthesesAndPrecedence() {
        var engine = CalculatorEngine()
        engine.setScientificMode(true)

        engine.apply(.leftParen)
        pressDigits("2", into: &engine)
        engine.apply(.binary(.add))
        pressDigits("3", into: &engine)
        engine.apply(.rightParen)
        engine.apply(.binary(.multiply))
        pressDigits("4", into: &engine)
        engine.apply(.equals)

        XCTAssertEqual(engine.state.displayText, "20")
    }

    func testScientificPowerAndRoot() {
        var engine = CalculatorEngine()
        engine.setScientificMode(true)

        pressDigits("2", into: &engine)
        engine.apply(.binary(.power))
        pressDigits("5", into: &engine)
        engine.apply(.equals)
        XCTAssertEqual(engine.state.displayText, "32")

        pressDigits("3", into: &engine)
        engine.apply(.binary(.root))
        pressDigits("8", into: &engine)
        engine.apply(.equals)

        XCTAssertEqual(engine.state.displayText, "2")
    }

    func testScientificTrigInRadians() {
        var engine = CalculatorEngine()
        engine.setScientificMode(true)
        engine.apply(.setAngleUnit(.radians))

        engine.apply(.constantPi)
        engine.apply(.unary(.sine))

        XCTAssertEqual(engine.state.displayText, "0")
    }

    func testScientificTrigInDegrees() {
        var engine = CalculatorEngine()
        engine.setScientificMode(true)
        engine.apply(.setAngleUnit(.degrees))

        pressDigits("90", into: &engine)
        engine.apply(.unary(.sine))

        XCTAssertAlmostEqual(displayValue(of: engine), 1.0, accuracy: 1e-9)
    }

    func testEEEntryWorkflow() {
        var engine = CalculatorEngine()
        engine.setScientificMode(true)

        pressDigits("1", into: &engine)
        engine.apply(.ee)
        pressDigits("3", into: &engine)
        engine.apply(.equals)

        XCTAssertEqual(engine.state.displayText, "1,000")
    }

    func testSecondFunctionInverseTrig() {
        var engine = CalculatorEngine()
        engine.setScientificMode(true)
        engine.apply(.setAngleUnit(.degrees))

        pressDigits("1", into: &engine)
        engine.apply(.unary(.inverseSine))

        XCTAssertEqual(engine.state.displayText, "90")
    }

    func testErrorAndRecovery() {
        var engine = CalculatorEngine()

        pressDigits("1", into: &engine)
        engine.apply(.binary(.divide))
        pressDigits("0", into: &engine)
        engine.apply(.equals)

        XCTAssertEqual(engine.state.displayText, "Error")

        engine.apply(.allClear)
        XCTAssertEqual(engine.state.displayText, "0")
    }

    func testSwitchingModesPreservesDisplayValue() {
        var engine = CalculatorEngine()

        pressDigits("123", into: &engine)
        engine.setScientificMode(true)

        XCTAssertEqual(engine.state.displayText, "123")

        engine.apply(.binary(.add))
        pressDigits("1", into: &engine)
        engine.apply(.equals)

        XCTAssertEqual(engine.state.displayText, "124")

        engine.setScientificMode(false)
        XCTAssertEqual(engine.state.displayText, "124")
    }

    func testClearEntryAndAllClearDiffer() {
        var engine = CalculatorEngine()

        pressDigits("42", into: &engine)
        engine.apply(.clearEntry)
        XCTAssertEqual(engine.state.displayText, "0")

        pressDigits("8", into: &engine)
        engine.apply(.memoryAdd)
        engine.apply(.allClear)
        engine.apply(.memoryRecall)

        XCTAssertEqual(engine.state.displayText, "8")
    }

    func testRandomProducesUnitInterval() {
        var engine = CalculatorEngine()
        engine.setScientificMode(true)

        engine.apply(.random)
        engine.apply(.equals)

        let value = displayValue(of: engine)
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThan(value, 1)
    }

    private func pressDigits(_ digits: String, into engine: inout CalculatorEngine) {
        for character in digits {
            guard let value = character.wholeNumberValue else { continue }
            engine.apply(.digit(value))
        }
    }

    private func displayValue(of engine: CalculatorEngine) -> Double {
        let cleaned = engine.state.displayText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "E", with: "e")
        return Double(cleaned) ?? 0
    }

    private func XCTAssertAlmostEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(abs(lhs - rhs), accuracy, file: file, line: line)
    }
}
