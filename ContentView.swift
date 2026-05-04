//
//  ContentView.swift
//  
//
//  Created by Ben Cerbin on 4/20/26.
//

import SwiftUI
import AVFoundation

private enum ButtonClickSound {
    private static let player: AVAudioPlayer? = {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("call-your-mom-low-button-click-v2.wav")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? makeClickData().write(to: fileURL, options: .atomic)
        }

        let player = try? AVAudioPlayer(contentsOf: fileURL)
        player?.volume = 1.0
        player?.prepareToPlay()
        return player
    }()

    static func perform(_ action: () -> Void) {
        player?.currentTime = 0
        player?.play()
        action()
    }

    private static func makeClickData() -> Data {
        let sampleRate = 44_100
        let channelCount = 1
        let bitsPerSample = 16
        let duration = 0.045
        let sampleCount = Int(Double(sampleRate) * duration)
        var pcmData = Data()

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let fade = exp(-78 * time)
            let lowTone = sin(2 * Double.pi * 185 * time)
            let warmEdge = sin(2 * Double.pi * 370 * time) * 0.28
            let sample = (lowTone + warmEdge) * fade * 0.55
            let clampedSample = max(-1, min(1, sample))
            var intSample = Int16(clampedSample * Double(Int16.max)).littleEndian
            Swift.withUnsafeBytes(of: &intSample) {
                pcmData.append(contentsOf: $0)
            }
        }

        let byteRate = sampleRate * channelCount * bitsPerSample / 8
        let blockAlign = channelCount * bitsPerSample / 8
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(36 + pcmData.count))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(channelCount))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(byteRate))
        data.appendLittleEndian(UInt16(blockAlign))
        data.appendLittleEndian(UInt16(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.appendLittleEndian(UInt32(pcmData.count))
        data.append(pcmData)
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) {
            append(contentsOf: $0)
        }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) {
            append(contentsOf: $0)
        }
    }
}

struct ContentView: View {
    @State private var health = 70
    @State private var mood = "🙂"

    var body: some View {
        VStack(spacing: 30) {
            
            Text("Call Your Mom")
                .font(.largeTitle)
                .bold()
            
            Text(mood)
                .font(.system(size: 80))
            
            Text("Health: \(health)")
                .font(.title2)
            
            Button("📞 Call Loved One") {
                ButtonClickSound.perform {
                    increaseHealth()
                }
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
            
        }
        .onAppear {
            startHealthDecay()
        }
        .padding()
    }
    
    // MARK: - Logic
    
    func increaseHealth() {
        health = min(health + 15, 100)
        updateMood()
    }
    
    func decreaseHealth() {
        health = max(health - 5, 0)
        updateMood()
    }
    
    func updateMood() {
        if health > 70 {
            mood = "😄"
        } else if health > 30 {
            mood = "😐"
        } else {
            mood = "😢"
        }
    }
    
    func startHealthDecay() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            decreaseHealth()
        }
    }
}
