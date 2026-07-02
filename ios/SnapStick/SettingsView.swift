//
//  SettingsView.swift
//  SnapStick
//
//  交互设置页：拍照声音开关 + 贴纸物理沙盒的移动速度与倾斜灵敏度。
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("声音") {
                    Toggle("马达声音", isOn: $settings.motorSoundEnabled)
                    Toggle("拍照声音", isOn: $settings.shutterSoundEnabled)
                }
                Section {
                    VStack(alignment: .leading) {
                        HStack { Text("显影时间"); Spacer()
                            Text(String(format: "%.1fs", settings.developTime)).foregroundColor(.secondary).monospaced() }
                        Slider(value: $settings.developTime, in: AppSettings.developTimeRange, step: 0.5)
                    }
                } header: {
                    Text("显影")
                } footer: {
                    Text("照片自动显影所需的时间；显影中摇一摇手机仍可立即加速出片。")
                }
                Section("贴纸物理") {
                    VStack(alignment: .leading) {
                        HStack { Text("移动速度"); Spacer()
                            Text(String(format: "%.2fx", settings.speed)).foregroundColor(.secondary).monospaced() }
                        Slider(value: $settings.speed, in: 0.5...6, step: 0.05)
                    }
                    VStack(alignment: .leading) {
                        HStack { Text("倾斜灵敏度"); Spacer()
                            Text(String(format: "%.2fx", settings.sensitivity)).foregroundColor(.secondary).monospaced() }
                        Slider(value: $settings.sensitivity, in: 0.5...3, step: 0.05)
                    }
                    Toggle("边缘碰撞震动", isOn: $settings.wallHitHaptic)
                    Button("重置为默认") {
                        settings.speed = AppSettings.defaultSpeed
                        settings.sensitivity = AppSettings.defaultSensitivity
                    }
                }
            }
            .navigationTitle("交互设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
