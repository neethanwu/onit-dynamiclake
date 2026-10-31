import Foundation
import Testing
@testable import OnitLake

@Test func wrapsBetweenWords() {
    #expect(LakeView.wrap("one two three four", width: 9) == ["one two", "three", "four"])
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
