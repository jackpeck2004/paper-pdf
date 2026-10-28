// Minimal assertions for Command Line Tools installations without XCTest.
// The same test methods use XCTest normally through Swift Package Manager.
import Foundation
class XCTestCase {}
var testFailures = 0
func fail(_ message: String, file: StaticString, line: UInt) {
    testFailures += 1
    print("FAIL \(file):\(line): \(message)")
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { fail("Expected true",file:file,line:line) } } catch { fail("\(error)",file:file,line:line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { fail("Expected false",file:file,line:line) } } catch { fail("\(error)",file:file,line:line) }
}
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T,_ b: @autoclosure () throws -> T,file: StaticString = #filePath,line: UInt = #line) {
    do { let x=try a(), y=try b(); if x != y { fail("\(x) != \(y)",file:file,line:line) } } catch { fail("\(error)",file:file,line:line) }
}
func XCTAssertEqual<T: BinaryFloatingPoint>(_ a: @autoclosure () throws -> T,_ b: @autoclosure () throws -> T,accuracy: T,file: StaticString = #filePath,line: UInt = #line) {
    do { let x=try a(), y=try b(); if abs(x-y)>accuracy { fail("\(x) != \(y) ± \(accuracy)",file:file,line:line) } } catch { fail("\(error)",file:file,line:line) }
}
func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T,_ b: @autoclosure () throws -> T,file: StaticString = #filePath,line: UInt = #line) {
    do { if try a() <= b() { fail("Expected greater value",file:file,line:line) } } catch { fail("\(error)",file:file,line:line) }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T,file: StaticString = #filePath,line: UInt = #line) {
    do { _=try value(); fail("Expected an error",file:file,line:line) } catch {}
}
func XCTUnwrap<T>(_ value: @autoclosure () throws -> T?,file: StaticString = #filePath,line: UInt = #line) throws -> T {
    if let result = try value() { return result }
    throw NSError(domain:"Test",code:1,userInfo:[NSLocalizedDescriptionKey:"Unexpected nil at \(file):\(line)"])
}
