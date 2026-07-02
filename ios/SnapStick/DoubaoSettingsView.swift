//
//  DoubaoSettingsView.swift
//  SnapStick
//
//  用户自带火山方舟 / 豆包 Key。App 不提供统一后端，也不内置开发者 Key。
//

import SwiftUI

struct DoubaoSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showAPIKey = false
    @State private var testPhase: TestPhase = .idle
    @State private var testTask: Task<Void, Never>?

    /// 连通性测试的状态机。失败时 reason 是中文文案 key（走本地化表），detail 原样展示。
    private enum TestPhase: Equatable {
        case idle
        case running
        case success(String)
        case failure(reason: String, detail: String?)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("请输入火山方舟 API Key", text: $settings.doubaoAPIKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("请输入火山方舟 API Key", text: $settings.doubaoAPIKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Button {
                            showAPIKey.toggle()
                        } label: {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Palette.klein)
                        .accessibilityLabel(Text(showAPIKey ? "隐藏 API Key" : "显示 API Key"))
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("API Key 只保存在本机钥匙串。识别时会从这台设备直接请求火山方舟，不经过拍立贴统一后端。")
                }

                Section {
                    TextField("例如 ep-xxxxxxxx 或 doubao-vision-...", text: $settings.doubaoModelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("模型 / Endpoint ID")
                } footer: {
                    Text("推荐填写你在火山方舟控制台创建的视觉理解模型 Endpoint ID；也可以填写账号可直接调用的豆包视觉模型 ID。")
                }

                Section {
                    TextField("接口地址", text: $settings.doubaoBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("恢复默认接口地址") {
                        settings.doubaoBaseURL = AppSettings.defaultDoubaoBaseURL
                    }
                } header: {
                    Text("高级")
                } footer: {
                    Text("通常不用修改。默认使用火山方舟北京区 Chat Completions 地址。")
                }

                Section {
                    Label(settings.doubaoConfigured ? "已配置" : "未配置完整",
                          systemImage: settings.doubaoConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundColor(settings.doubaoConfigured ? .green : .secondary)
                }

                Section {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            if testPhase == .running {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!settings.doubaoConfigured || testPhase == .running)

                    switch testPhase {
                    case .success(let reply):
                        testResultRow(icon: "checkmark.circle.fill", tint: .green,
                                      title: "连接成功", reason: nil, detail: reply)
                    case .failure(let reason, let detail):
                        testResultRow(icon: "xmark.circle.fill", tint: .red,
                                      title: "连接失败", reason: reason, detail: detail)
                    case .idle, .running:
                        EmptyView()
                    }
                } header: {
                    Text("连接测试")
                } footer: {
                    Text(settings.doubaoConfigured
                         ? "向豆包发送一句「hi」，验证 API Key、模型与接口地址是否可用。"
                         : "请先填写 API Key 和模型 ID。")
                }
            }
            .onChange(of: settings.doubaoAPIKey) { resetTest() }
            .onChange(of: settings.doubaoModelID) { resetTest() }
            .onChange(of: settings.doubaoBaseURL) { resetTest() }
            .navigationTitle("豆包 API")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        normalize()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                testTask?.cancel()
                normalize()
            }
        }
    }

    private func testResultRow(icon: String, tint: Color, title: LocalizedStringKey,
                               reason: String?, detail: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let reason {
                    Text(LocalizedStringKey(reason))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(tint)
        }
    }

    private func runTest() {
        normalize()
        guard settings.doubaoConfigured else { return }
        testPhase = .running
        testTask = Task {
            do {
                let reply = try await DoubaoAPI.sayHi(apiKey: settings.doubaoAPIKey,
                                                      modelID: settings.doubaoModelID,
                                                      baseURL: settings.doubaoBaseURL)
                testPhase = .success(reply)
            } catch is CancellationError {
                return
            } catch let error as DoubaoAPI.APIError {
                testPhase = .failure(reason: Self.failureReason(for: error),
                                     detail: Self.failureDetail(for: error))
            } catch {
                testPhase = .failure(reason: "网络请求失败", detail: error.localizedDescription)
            }
        }
    }

    private func resetTest() {
        testTask?.cancel()
        testPhase = .idle
    }

    private static func failureReason(for error: DoubaoAPI.APIError) -> String {
        switch error {
        case .badURL: "接口地址无效"
        case .http: "服务器返回错误"
        case .badResponse: "返回内容无法解析"
        }
    }

    private static func failureDetail(for error: DoubaoAPI.APIError) -> String? {
        guard case .http(let code, let message) = error else { return nil }
        if let message, !message.isEmpty {
            return "HTTP \(code) · \(message)"
        }
        return "HTTP \(code)"
    }

    private func normalize() {
        settings.doubaoAPIKey = settings.doubaoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.doubaoModelID = settings.doubaoModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.doubaoBaseURL = settings.doubaoBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
