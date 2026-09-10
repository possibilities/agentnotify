import Foundation
import NotifyCore

final class ArgumentsTests: CheckCase {
    func testLegacyActionsAndEscaping() throws {
        let result = try Arguments.parse(["-message", "\\[Build] Done", "-action", "Ship, Hold", "-action", "Inspect", "-reply", "", "-timeout", "2.5"])
        expectEqual(result.params["message"] as? String, "[Build] Done")
        expectEqual(result.params["actions"] as? [String], ["Ship", "Hold", "Inspect"])
        expectEqual(result.params["reply"] as? String, "")
        expectEqual(result.params["timeout"] as? Double, 2.5)
    }
    func testPipedMessageAndListGrammar() throws {
        expectEqual(try Arguments.parse([], stdin: "hello\nthere\r\n").params["message"] as? String, "hello\nthere")
        expectEqual(try Arguments.parse(["-list", "PENDING"]).params["filter"] as? String, "pending")
        let replace = try Arguments.parse(["-remove", "build", "-group", "build", "-message", "New"])
        expectEqual(replace.removeFirst, "build"); expectEqual(replace.method, "send")
        expectEqual(Arguments.tsv([], pending: false), "")
    }
    func testModernTypedArguments() throws {
        let result = try Arguments.parse(["send", "--message=Hello", "--actions", "[\"one,two\",\"Same\"]", "--timeout", "2", "--ignoreDnD"])
        expectFalse(result.legacy); expectEqual(result.params["actions"] as? [String], ["one,two", "Same"])
        expectEqual(result.params["ignoreDnD"] as? Bool, true)
        expectThrows(try Arguments.parse(["send", "--message", "Hi", "--extra", "no"]))
        expectThrows(try Arguments.parse(["-message", "Hi", "-timeout", "nan"]))
        let batch = try Arguments.parse(["statusBatch", "--items", "[{\"id\":\"one\",\"expectedRevision\":2}]", "--state", "snooze", "--in", "1h"])
        expectEqual((batch.params["items"] as? [[String: Any]])?.first?["id"] as? String, "one")
        expectEqual(batch.params["in"] as? String, "1h")
    }
    func testShortcutJSONArguments() throws {
        let assigned = try Arguments.parse([
            "setPreferences",
            "--completeAllShortcut",
            "{\"keyCode\":53,\"key\":\"⎋\",\"modifiers\":[\"control\",\"command\"]}",
        ])
        let shortcut = assigned.params["completeAllShortcut"] as? [String: Any]
        expectEqual(shortcut?["keyCode"] as? Int, 53)
        expectEqual(shortcut?["key"] as? String, "⎋")
        expectEqual(shortcut?["modifiers"] as? [String], ["control", "command"])

        let cleared = try Arguments.parse(["setPreferences", "--completeAllShortcut=null"])
        expectTrue(cleared.params["completeAllShortcut"] is NSNull)
        for invalid in ["[]", "true", "\"shortcut\"", "{bad json}"] {
            expectThrows(try Arguments.parse(["setPreferences", "--completeAllShortcut", invalid]))
        }
    }
    func testScheduleValidation() throws {
        expectEqual(try Schedule.duration("1.5h"), 5400)
        for invalid in ["0", "-5", "NaN", "5z", "infinity", "1m4s"] { expectThrows(try Schedule.duration(invalid)) }
        expectThrows(try Schedule.date("29:99"))
    }
    func testCatalogHasMatchingToolSchemas() {
        expectEqual(Catalog.tools.count, Catalog.operations.count)
        expectTrue(Catalog.tools.allSatisfy { ($0["inputSchema"] as? [String: Any])?["additionalProperties"] as? Bool == false })
    }
}
