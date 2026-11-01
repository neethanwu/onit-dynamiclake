import Foundation
import Testing
@testable import OnitLake

@Test func wrapsBetweenWords() {
    #expect(LakeView.wrap("one two three four", width: 9) == ["one two", "three", "four"])
    let reason = "A file or folder it needs is missing. It may have been moved, renamed or deleted."
    let lines = LakeView.wrap(reason, width: 74)
    #expect(lines.count == 2 && lines.allSatisfy { $0.count <= 74 && $0.count > 20 })
}

@Test func encodesWholeNumbersAsIntegers() {
    let json: JSON = ["size": 14, "value": 0.5]
    #expect(String(decoding: json.encoded(), as: UTF8.self) == #"{"size":14,"value":0.5}"#)
}

@Test func emptyTextIsNeverSent() {
    // DynamicLake rejects a text component with an empty string.
    #expect(C.text("")["text"]?.string?.isEmpty == false)
}

@Test func tokensUseOnlyIdentifierCharacters() {
    let job = Job(id: "launchd:com.example.my job/with odd chars", source: .launchd, label: "x", name: "x",
                  schedule: Schedule(), arguments: [])
    let token = Token.of(job)
    #expect(token.allSatisfy { $0.isLetter || $0.isNumber || "._:-".contains($0) })
}

@Test func readsServicesFromTheGUIDomain() {
    let output = """
    gui/501 = {
    \ttype = gui
    \tservices = {
    \t\t       0      0 \tcom.example.idle
    \t\t     853      - \tdev.example.daemon
    \t\t       0      1 \tcom.example.failed
    \t\t       0   (pe) \tcom.example.note
    \t}
    \tunmanaged processes = {
    \t\t     999      - \tnot.a.service
    \t}
    }
    """
    let services = LaunchdScanner.parseServices(output)
    #expect(services.count == 4)
    #expect(services["com.example.idle"]?.pid == nil)
    #expect(services["dev.example.daemon"]?.pid == 853)
    #expect(services["com.example.failed"]?.status == 1)
    #expect(services["not.a.service"] == nil)
}
