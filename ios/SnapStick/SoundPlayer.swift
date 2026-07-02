//
//  SoundPlayer.swift
//  SnapStick
//
//  实时合成音效（无需音频素材），对应网页版的 Web Audio：
//  快门「咔」（三角波衰减）+ 出纸马达声（锯齿波 + 低频抖动 + 包络）。
//  外加快门触感反馈。使用 .ambient 分类：与背景音乐共存、遵从静音键。
//

import AVFoundation
import UIKit

@MainActor
final class SoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var started = false

    private func ensureStarted() {
        guard !started else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do { try engine.start(); started = true } catch { started = false }
    }

    /// 快门「咔」：520Hz 三角波，0.18s 指数衰减。
    func playShutter() {
        ensureStarted()
        let sr = 44100.0, dur = 0.18
        let buffer = makeBuffer(seconds: dur) { t in
            let phase = 520.0 * t
            let tri = (2.0 / .pi) * asin(sin(2.0 * .pi * phase))
            let env = exp(-t / 0.05) * 0.18
            return Float(tri * env)
        }
        schedule(buffer)
        _ = sr
    }

    /// 出纸马达声：78Hz 锯齿波 + 22Hz 抖动调频，带起落包络。
    func playMotor(seconds: Double) {
        ensureStarted()
        var phase = 0.0
        let dt = 1.0 / 44100.0
        let buffer = makeBuffer(seconds: seconds) { t in
            let inst = 78.0 + 8.0 * sin(2.0 * .pi * 22.0 * t)   // LFO 调频
            phase += inst * dt
            let saw = 2.0 * (phase - (phase + 0.5).rounded(.down)) // [-1,1] 锯齿
            // 包络：0.15s 渐起到 0.05，结尾 0.25s 渐落
            var env = 0.05
            if t < 0.15 { env = 0.05 * (t / 0.15) }
            else if t > seconds - 0.25 { env = 0.05 * max(0, (seconds - t) / 0.25) }
            return Float(saw * env)
        }
        schedule(buffer)
    }

    func shutterHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    /// 贴纸砸到边缘时的轻触感。撞墙是高频事件，复用常驻 generator 并预热以降低延迟。
    private let wallGen = UIImpactFeedbackGenerator(style: .light)
    func wallHitHaptic() {
        wallGen.impactOccurred(intensity: 0.7)
        wallGen.prepare()
    }

    // MARK: - 工具

    private func makeBuffer(seconds: Double, sample: (Double) -> Float) -> AVAudioPCMBuffer {
        let sr = 44100.0
        let frames = AVAudioFrameCount(seconds * sr)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let ptr = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            ptr[i] = sample(Double(i) / sr)
        }
        return buffer
    }

    private func schedule(_ buffer: AVAudioPCMBuffer) {
        guard started else { return }
        player.scheduleBuffer(buffer, at: nil, options: [])
        if !player.isPlaying { player.play() }
    }
}
