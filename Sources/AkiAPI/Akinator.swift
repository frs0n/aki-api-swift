import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AkinatorRegion: String, CaseIterable, Sendable {
    case en, ar, cn, de, es, fr, il, it, jp, kr, nl, pl, pt, ru, tr, id
}

public enum AkinatorAnswer: Int, CaseIterable, Sendable {
    case yes = 0
    case no = 1
    case dontKnow = 2
    case probably = 3
    case probablyNot = 4
}

public struct AkinatorStep: Decodable, Sendable {
    public let completion: String?
    public let akitude: String?
    public let step: String
    public let progression: String
    public let questionID: String?
    public let question: String

    enum CodingKeys: String, CodingKey {
        case completion, akitude, step, progression, question
        case questionID = "question_id"
    }
}

public struct AkinatorGuess: Decodable, Sendable {
    public let completion: String
    public let descriptionProposition: String
    public let flagPhoto: String
    public let idBaseProposition: String
    public let idProposition: String
    public let nameProposition: String
    public let nbElements: Int
    public let photo: String
    public let pseudo: String
    public let valideContrainte: String

    enum CodingKeys: String, CodingKey {
        case completion, photo, pseudo
        case descriptionProposition = "description_proposition"
        case flagPhoto = "flag_photo"
        case idBaseProposition = "id_base_proposition"
        case idProposition = "id_proposition"
        case nameProposition = "name_proposition"
        case nbElements = "nb_elements"
        case valideContrainte = "valide_contrainte"
    }
}

public enum AkinatorResponse: Sendable {
    case step(AkinatorStep)
    case guess(AkinatorGuess)
}

public enum AkinatorError: Error, LocalizedError, Sendable {
    case missingSession
    case badStatus(Int)
    case badStartPage
    case blockedByAkinator
    case api(String, AkinatorRegion)

    public var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Could not find the game session. Please make sure you have started the game."
        case .badStatus(let status):
            return "Akinator returned HTTP \(status)."
        case .badStartPage:
            return "Akinator start page did not contain a session, signature, question, or answers."
        case .blockedByAkinator:
            return "Akinator blocked this request. Try another network or region."
        case .api(let completion, let region):
            switch completion {
            case "KO - SERVER DOWN":
                return "Akinator servers are down for the \"\(region.rawValue)\" region. \(completion)"
            case "KO - TECHNICAL ERROR":
                return "Akinator had a technical error for the \"\(region.rawValue)\" region. \(completion)"
            case "KO - INCORRECT PARAMETER":
                return "Wrong parameter: session, region, or signature. \(completion)"
            case "KO - TIMEOUT":
                return "Your Akinator session has timed out. \(completion)"
            case "WARN - NO QUESTION":
                return "No question found. \(completion)"
            case "KO - MISSING PARAMETERS":
                return "Akinator needs more parameters. \(completion)"
            default:
                return "Unknown Akinator error: \(completion)"
            }
        }
    }
}

public final class Akinator: @unchecked Sendable {
    public private(set) var currentStep = 0
    public let region: AkinatorRegion
    public let childMode: Bool
    public private(set) var progress = 0.0
    public private(set) var question = ""
    public private(set) var answers: [String]
    public private(set) var guess: AkinatorGuess?

    private let baseURL: URL
    private let session: URLSession
    private var gameSession: String?
    private var signature: String?

    public init(region: AkinatorRegion, childMode: Bool = false, session: URLSession = .shared) {
        self.region = region
        self.childMode = childMode
        self.session = session
        self.baseURL = URL(string: "https://\(region.rawValue).akinator.com")!
        self.answers = region.defaultAnswers
    }

    @discardableResult
    public func start() async throws -> Akinator {
        let text = try await postText(path: "/game", fields: ["sid": "1", "cm": "\(childMode)"])
        if text.isCloudflareBlockPage {
            throw AkinatorError.blockedByAkinator
        }

        guard
            let parsedQuestion = text.firstMatch(#"<p class="question-text" id="question-label">(.+?)</p>"#),
            let parsedSession = text.firstMatch(#"#session'\)\.val\('(.+?)'\)"#) ?? text.firstMatch(#"session: '(.+?)'"#),
            let parsedSignature = text.firstMatch(#"#signature'\)\.val\('(.+?)'\)"#) ?? text.firstMatch(#"signature: '(.+?)'"#)
        else {
            throw AkinatorError.badStartPage
        }

        let parsedAnswers = [
            #"id="a_yes" onclick="chooseAnswer\(0\)">(.+?)</a>"#,
            #"id="a_no" onclick="chooseAnswer\(1\)">(.+?)</a>"#,
            #"id="a_dont_know" onclick="chooseAnswer\(2\)">(.+?)</a>"#,
            #"id="a_probably" onclick="chooseAnswer\(3\)">(.+?)</a>"#,
            #"id="a_probaly_not" onclick="chooseAnswer\(4\)">(.+?)</a>"#
        ].compactMap { text.firstMatch($0)?.htmlDecoded() }

        question = parsedQuestion.htmlDecoded()
        gameSession = parsedSession
        signature = parsedSignature
        answers = parsedAnswers.count == 5 ? parsedAnswers : region.defaultAnswers
        return self
    }

    public func step(_ answer: AkinatorAnswer) async throws -> AkinatorResponse {
        let result = try await post(path: "/answer", fields: stateFields([
            "answer": "\(answer.rawValue)",
            "step_last_proposition": ""
        ])).0

        if let guess = try? JSONDecoder().decode(AkinatorGuess.self, from: result) {
            self.guess = guess
            return .guess(guess)
        }

        let step = try decodeStep(result)
        apply(step)
        return .step(step)
    }

    public func back() async throws -> AkinatorStep {
        let step = try decodeStep(try await post(path: "/cancel_answer", fields: stateFields()).0)
        apply(step)
        return step
    }

    public func `continue`() async throws -> AkinatorStep {
        let step = try decodeStep(try await post(path: "/exclude", fields: stateFields()).0)
        apply(step)
        return step
    }

    private func stateFields(_ extra: [String: String] = [:]) throws -> [String: String] {
        guard let gameSession, let signature else { throw AkinatorError.missingSession }
        return [
            "step": "\(currentStep)",
            "progression": "\(progress)",
            "sid": "1",
            "cm": "\(childMode)",
            "session": gameSession,
            "signature": signature
        ].merging(extra) { _, new in new }
    }

    private func apply(_ step: AkinatorStep) {
        currentStep = Int(step.step) ?? currentStep
        progress = Double(step.progression) ?? progress
        question = step.question
    }

    private func decodeStep(_ data: Data) throws -> AkinatorStep {
        let step = try JSONDecoder().decode(AkinatorStep.self, from: data)
        if let completion = step.completion, completion.hasPrefix("KO") || completion.hasPrefix("WARN") {
            throw AkinatorError.api(completion, region)
        }
        return step
    }

    private func postText(path: String, fields: [String: String]) async throws -> String {
        let (data, _) = try await post(path: path, fields: fields)
        return String(decoding: data, as: UTF8.self)
    }

    private func post(path: String, fields: [String: String]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,application/json;q=0.8,*/*;q=0.7", forHTTPHeaderField: "Accept")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(baseURL.absoluteString + "/", forHTTPHeaderField: "Referer")
        request.httpBody = fields.formBody

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let text = String(decoding: data, as: UTF8.self)
            if text.isCloudflareBlockPage {
                throw AkinatorError.blockedByAkinator
            }
            throw AkinatorError.badStatus(http.statusCode)
        }
        return (data, response)
    }
}

extension Dictionary where Key == String, Value == String {
    var formBody: Data {
        map { key, value in "\(key.urlFormEscaped)=\(value.urlFormEscaped)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

extension AkinatorRegion {
    var defaultAnswers: [String] {
        switch self {
        case .cn:
            return ["是", "不是", "不知道", "可能是", "可能不是"]
        default:
            return ["Yes", "No", "Don't know", "Probably", "Probably not"]
        }
    }
}

extension String {
    var urlFormEscaped: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }

    func firstMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range), match.numberOfRanges > 1 else { return nil }
        return Range(match.range(at: 1), in: self).map { String(self[$0]) }
    }

    func htmlDecoded() -> String {
        var text = self
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")

        let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#)
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed() ?? []
        for match in matches {
            guard
                let range = Range(match.range(at: 0), in: text),
                let valueRange = Range(match.range(at: 1), in: text),
                let scalar = UnicodeScalar(Int(text[valueRange]) ?? -1)
            else { continue }
            text.replaceSubrange(range, with: String(Character(scalar)))
        }
        return text
    }

    var isCloudflareBlockPage: Bool {
        contains("id=\"cf-wrapper\"") || contains("cf-error-details") || contains("cf-cookie-error")
    }
}
