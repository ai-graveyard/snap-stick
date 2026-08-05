//
//  DoubaoAPI.swift
//  SnapStick
//
//  火山方舟 / 豆包 的最小客户端（OpenAI 兼容协议）。两个调用方：
//  「豆包 API」设置页的连通性测试（sayHi → chat/completions），
//  以及 AI 卡通贴纸（AIRender → images/generations，seedream 图生图）。
//  baseURL 是 API 根地址（…/api/v3），端点路径在这里拼接。
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
        let data = try await send(
            ChatRequest(model: modelID, messages: [.init(role: "user", content: text)], maxTokens: 64),
            to: endpointURL(baseURL, path: "/chat/completions"),
            apiKey: apiKey, timeout: 20)

        let reply = (try? JSONDecoder().decode(ChatResponse.self, from: data))?
            .choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reply, !reply.isEmpty else { throw APIError.badResponse }
        return reply
    }

    /// 图生图：把照片交给生成模型按 prompt 出图（AI 卡通贴纸用），返回解码前的图片数据。
    static func generateImage(prompt: String, imageDataURL: String,
                              apiKey: String, modelID: String, baseURL: String,
                              timeout: TimeInterval) async throws -> Data {
        let data = try await send(
            ImageRequest(model: modelID, prompt: prompt, image: imageDataURL),
            to: endpointURL(baseURL, path: "/images/generations"),
            apiKey: apiKey, timeout: timeout)

        guard let b64 = (try? JSONDecoder().decode(ImageResponse.self, from: data))?
                .data.first?.b64JSON,
              let image = Data(base64Encoded: b64) else {
            throw APIError.badResponse
        }
        return image
    }

    // MARK: - 请求发送

    /// 从根地址拼端点；容错用户粘贴了完整端点地址（剥掉已知路径再拼）。
    private static func endpointURL(_ baseURL: String, path: String) throws -> URL {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        for known in ["/chat/completions", "/images/generations"] where root.hasSuffix(known) {
            root.removeLast(known.count)
        }
        guard let url = URL(string: root + path),
              url.scheme?.lowercased().hasPrefix("http") == true else {
            throw APIError.badURL
        }
        return url
    }

    private static func send<Body: Encodable>(_ body: Body, to url: URL,
                                              apiKey: String, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message
            throw APIError.http(code: http.statusCode, message: message)
        }
        return data
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

    /// 图生图请求：除 response_format 改用 b64_json（省一次图片下载），
    /// 其余参数与 web 版 /api/generate 完全一致。
    private struct ImageRequest: Encodable {
        let model: String
        let prompt: String
        let image: String
        let responseFormat = "b64_json"
        let size = "2K"
        let sequentialImageGeneration = "disabled"
        let watermark = true
        let stream = false

        enum CodingKeys: String, CodingKey {
            case model, prompt, image, size, watermark, stream
            case responseFormat = "response_format"
            case sequentialImageGeneration = "sequential_image_generation"
        }
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }

        let choices: [Choice]
    }

    private struct ImageResponse: Decodable {
        struct Item: Decodable {
            let b64JSON: String?

            enum CodingKeys: String, CodingKey {
                case b64JSON = "b64_json"
            }
        }

        let data: [Item]
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail?
    }
}
