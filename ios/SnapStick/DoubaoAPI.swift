//
//  DoubaoAPI.swift
//  SnapStick
//
//  火山方舟 / 豆包 Chat Completions 的最小客户端（OpenAI 兼容协议）。
//  目前只有「豆包 API」设置页的连通性测试在用（发一句 hi）；
//  后续若要做云端识别，可在此基础上扩展多模态消息。
//

import Foundation

enum DoubaoAPI {
    enum APIError: Error {
        case badURL
        case http(code: Int, message: String?)
        case badResponse
    }

    /// 发一句「hi」做连通性测试，返回模型回复的文本。
    static func sayHi(apiKey: String, modelID: String, baseURL: String) async throws -> String {
        try await chat(text: "hi", apiKey: apiKey, modelID: modelID, baseURL: baseURL)
    }

    /// 单轮纯文本对话，返回助手回复。
    static func chat(text: String, apiKey: String, modelID: String, baseURL: String) async throws -> String {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased().hasPrefix("http") == true else {
            throw APIError.badURL
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: modelID,
            messages: [.init(role: "user", content: text)],
            maxTokens: 64
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
            throw APIError.http(code: http.statusCode, message: message)
        }

        let reply = (try? JSONDecoder().decode(ChatResponse.self, from: data))?
            .choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reply, !reply.isEmpty else { throw APIError.badResponse }
        return reply
    }

    // MARK: - 报文结构

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case model, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }

        let choices: [Choice]
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail?
    }
}
