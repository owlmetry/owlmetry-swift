import Foundation

/// A complete questionnaire spec fetched from `GET /v1/questionnaires/:slug`.
/// Public so consumers can render it manually via `OwlQuestionnaireView`.
public struct OwlQuestionnaire: Sendable, Equatable {
    public let id: String
    public let slug: String
    public let name: String
    public let description: String?
    public let schema: OwlQuestionnaireSchema

    public init(
        id: String,
        slug: String,
        name: String,
        description: String?,
        schema: OwlQuestionnaireSchema
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.description = description
        self.schema = schema
    }
}

public struct OwlQuestionnaireSchema: Sendable, Equatable {
    public let version: Int
    public let questions: [OwlQuestionnaireQuestion]

    public init(version: Int, questions: [OwlQuestionnaireQuestion]) {
        self.version = version
        self.questions = questions
    }
}

public struct OwlQuestionnaireChoiceOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
}

public enum OwlQuestionnaireQuestion: Sendable, Equatable, Identifiable {
    case text(OwlQuestionnaireTextQuestion)
    case singleChoice(OwlQuestionnaireSingleChoiceQuestion)
    case multiChoice(OwlQuestionnaireMultiChoiceQuestion)
    case rating(OwlQuestionnaireRatingQuestion)
    case nps(OwlQuestionnaireNpsQuestion)

    public var id: String {
        switch self {
        case .text(let q): return q.id
        case .singleChoice(let q): return q.id
        case .multiChoice(let q): return q.id
        case .rating(let q): return q.id
        case .nps(let q): return q.id
        }
    }

    public var title: String {
        switch self {
        case .text(let q): return q.title
        case .singleChoice(let q): return q.title
        case .multiChoice(let q): return q.title
        case .rating(let q): return q.title
        case .nps(let q): return q.title
        }
    }

    public var subtitle: String? {
        switch self {
        case .text(let q): return q.subtitle
        case .singleChoice(let q): return q.subtitle
        case .multiChoice(let q): return q.subtitle
        case .rating(let q): return q.subtitle
        case .nps(let q): return q.subtitle
        }
    }

    public var required: Bool {
        switch self {
        case .text(let q): return q.required
        case .singleChoice(let q): return q.required
        case .multiChoice(let q): return q.required
        case .rating(let q): return q.required
        case .nps(let q): return q.required
        }
    }
}

public struct OwlQuestionnaireTextQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
    public let placeholder: String?
    public let multiline: Bool
}

public struct OwlQuestionnaireSingleChoiceQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
    public let options: [OwlQuestionnaireChoiceOption]
}

public struct OwlQuestionnaireMultiChoiceQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
    public let options: [OwlQuestionnaireChoiceOption]
}

public struct OwlQuestionnaireRatingQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
    public let scale: Int  // V1: always 5
}

public struct OwlQuestionnaireNpsQuestion: Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let required: Bool
}

/// Heterogeneous answer value. Wire encodes as the underlying type directly,
/// not as a tagged union — the server validates against the schema.
public enum OwlQuestionnaireAnswerValue: Sendable, Equatable {
    case text(String)
    case choice(String)         // option id
    case choices([String])      // option ids
    case rating(Int)            // 1...scale
    case nps(Int)               // 0...10
}

/// Receipt returned by `POST /v1/questionnaires/:slug/responses`.
public struct OwlQuestionnaireReceipt: Sendable, Equatable {
    public let id: String
    public let createdAt: Date

    public init(id: String, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

/// Reason a questionnaire is not eligible to present right now. Mirrors the
/// server's eligibility envelope.
public enum OwlQuestionnaireIneligibleReason: String, Sendable {
    case alreadyResponded = "already_responded"
    case globallyDismissed = "globally_dismissed"
    case inactive = "inactive"
}

/// Errors surfaced by `Owl.fetchQuestionnaire` / `Owl.submitQuestionnaireResponse` /
/// `Owl.dismissQuestionnaires`. Non-eligible fetches return `nil` instead of throwing.
public enum OwlQuestionnaireError: Error, LocalizedError, Equatable, Sendable {
    case notConfigured
    case slugNotFound
    case invalidAnswers(String)
    case serverError(statusCode: Int, body: String?)
    case transportFailure(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Owlmetry is not configured. Call Owl.configure(...) first."
        case .slugNotFound:
            return "Questionnaire slug not found."
        case .invalidAnswers(let msg):
            return "Invalid answers: \(msg)"
        case .serverError(let code, let body):
            if let body, !body.isEmpty { return "Server returned \(code): \(body)" }
            return "Server returned \(code)"
        case .transportFailure(let msg):
            return msg
        }
    }
}

// MARK: - Codable wire format

extension OwlQuestionnaire: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, slug, name, description, schema
    }
}

extension OwlQuestionnaireSchema: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, questions
    }
}

extension OwlQuestionnaireChoiceOption: Codable {}

extension OwlQuestionnaireQuestion: Codable {
    private enum CodingKeys: String, CodingKey { case type }
    private enum QuestionType: String, Codable {
        case text, single_choice, multi_choice, rating, nps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(QuestionType.self, forKey: .type)
        switch type {
        case .text:          self = .text(try OwlQuestionnaireTextQuestion(from: decoder))
        case .single_choice: self = .singleChoice(try OwlQuestionnaireSingleChoiceQuestion(from: decoder))
        case .multi_choice:  self = .multiChoice(try OwlQuestionnaireMultiChoiceQuestion(from: decoder))
        case .rating:        self = .rating(try OwlQuestionnaireRatingQuestion(from: decoder))
        case .nps:           self = .nps(try OwlQuestionnaireNpsQuestion(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let q):         try q.encodeWithType(to: encoder, type: "text")
        case .singleChoice(let q): try q.encodeWithType(to: encoder, type: "single_choice")
        case .multiChoice(let q):  try q.encodeWithType(to: encoder, type: "multi_choice")
        case .rating(let q):       try q.encodeWithType(to: encoder, type: "rating")
        case .nps(let q):          try q.encodeWithType(to: encoder, type: "nps")
        }
    }
}

private protocol _TypedQuestion: Codable {
    func encodeWithType(to encoder: Encoder, type: String) throws
}

extension OwlQuestionnaireTextQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, required, placeholder, multiline, type
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        multiline = (try c.decodeIfPresent(Bool.self, forKey: .multiline)) ?? false
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "text") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
        try c.encodeIfPresent(placeholder, forKey: .placeholder)
        try c.encode(multiline, forKey: .multiline)
    }
}

extension OwlQuestionnaireSingleChoiceQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey { case id, title, subtitle, required, options, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
        options = try c.decode([OwlQuestionnaireChoiceOption].self, forKey: .options)
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "single_choice") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
        try c.encode(options, forKey: .options)
    }
}

extension OwlQuestionnaireMultiChoiceQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey { case id, title, subtitle, required, options, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
        options = try c.decode([OwlQuestionnaireChoiceOption].self, forKey: .options)
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "multi_choice") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
        try c.encode(options, forKey: .options)
    }
}

extension OwlQuestionnaireRatingQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey { case id, title, subtitle, required, scale, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
        scale = try c.decode(Int.self, forKey: .scale)
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "rating") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
        try c.encode(scale, forKey: .scale)
    }
}

extension OwlQuestionnaireNpsQuestion: _TypedQuestion {
    enum CodingKeys: String, CodingKey { case id, title, subtitle, required, type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        required = try c.decode(Bool.self, forKey: .required)
    }
    public func encode(to encoder: Encoder) throws { try encodeWithType(to: encoder, type: "nps") }
    func encodeWithType(to encoder: Encoder, type: String) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(required, forKey: .required)
    }
}

// MARK: - Answer payload encoder

/// Internal — encodes `[String: OwlQuestionnaireAnswerValue]` into the wire
/// shape (`Record<questionId, string | string[] | int>`).
struct OwlQuestionnaireAnswersWire: Encodable {
    let answers: [String: OwlQuestionnaireAnswerValue]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        for (key, value) in answers {
            let k = DynamicKey(stringValue: key)!
            switch value {
            case .text(let s):        try c.encode(s, forKey: k)
            case .choice(let s):      try c.encode(s, forKey: k)
            case .choices(let arr):   try c.encode(arr, forKey: k)
            case .rating(let n):      try c.encode(n, forKey: k)
            case .nps(let n):         try c.encode(n, forKey: k)
            }
        }
    }
}

// Wire-format helpers used by EventTransport.

struct QuestionnaireFetchEnvelope: Decodable {
    let eligible: Bool
    let reason: String?
    let questionnaire: OwlQuestionnaire?
}

struct QuestionnaireSubmitRequestBody: Encodable {
    let bundle_id: String
    let session_id: String?
    let user_id: String?
    let answers: OwlQuestionnaireAnswersWire
    let app_version: String?
    let sdk_name: String?
    let sdk_version: String?
    let environment: String?
    let device_model: String?
    let os_version: String?
    let is_dev: Bool
}

struct QuestionnaireSubmitResponseBody: Decodable {
    let id: String
    let created_at: String
}

struct QuestionnaireDismissRequestBody: Encodable {
    let bundle_id: String
    let user_id: String
}

struct QuestionnaireDismissResponseBody: Decodable {
    let dismissed_at: String
}
