import XCTest
@testable import AkiAPI

final class AkinatorTests: XCTestCase {
    func testRegionsMatchNodePackage() {
        XCTAssertEqual(AkinatorRegion.allCases.map(\.rawValue), [
            "en", "ar", "cn", "de", "es", "fr", "il", "it",
            "jp", "kr", "nl", "pl", "pt", "ru", "tr", "id"
        ])
    }

    func testFormEncodingAndHTMLDecoding() {
        XCTAssertEqual(["a": "x y", "b": "1&2"].formBodyString.sorted().joined(separator: "&"), "a=x%20y&b=1%262")
        XCTAssertEqual("Don&#39;t know &amp; yes".htmlDecoded(), "Don't know & yes")
    }

    func testCloudflareErrorMessage() {
        XCTAssertEqual(AkinatorError.blockedByAkinator.localizedDescription, "Akinator blocked this request. Try another network or region.")
    }

    func testQuestionRegexStopsAtFirstClosingParagraph() {
        let html = #"<p class="question-text" id="question-label">Is your character real?</p><p>Other text</p>"#
        XCTAssertEqual(html.firstMatch(#"<p class="question-text" id="question-label">(.+?)</p>"#), "Is your character real?")
    }

    func testDecodesFinalGuess() throws {
        let data = #"{"completion":"OK","id_proposition":"463316","id_base_proposition":"5229448","valide_contrainte":"1","name_proposition":"\u5f20\u96ea\u5cf0","description_proposition":"\u6296\u97f3\u7f51\u7ea2 \u8001\u5e08","flag_photo":"3","photo":"https:\/\/photos.clarinea.fr\/BL_11_cn\/600\/partenaire\/e\/5229448__75036093.jpg","pseudo":"X","nb_elements":1,"no_question":"0","step":"5"}"#.data(using: .utf8)!
        let guess = try JSONDecoder().decode(AkinatorGuess.self, from: data)
        XCTAssertEqual(guess.nameProposition, "张雪峰")
        XCTAssertEqual(guess.valideContrainte, "1")
    }
}

private extension Dictionary where Key == String, Value == String {
    var formBodyString: [String] {
        String(decoding: formBody, as: UTF8.self).split(separator: "&").map(String.init)
    }
}
