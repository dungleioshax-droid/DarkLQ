//
//  keepalive.swift
//  External-DarkSword
//
//  Created by Le Tien Dat on 7/8/26.
//

import AVFoundation

private var kaPlayer: AVAudioPlayer?
var kaEnabled = false

func toggleKeepAlive(logger: ((String) -> Void)? = nil) {
    if kaEnabled {
        kaPlayer?.stop()
        kaPlayer = nil
        kaEnabled = false
        logger?("[KeepAlive] Disabled.")
        return
    }

    do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
        try session.setActive(true)
    } catch {
        logger?("[KeepAlive] Audio session failed: \(error)")
        return
    }

    let fileURL = kaWavURL()

    if !FileManager.default.fileExists(atPath: fileURL.path) {
        makeSilentWav(at: fileURL)
    }

    do {
        kaPlayer = try AVAudioPlayer(contentsOf: fileURL)
        kaPlayer?.numberOfLoops = -1
        kaPlayer?.volume = 0.0
        kaPlayer?.prepareToPlay()
        kaPlayer?.play()
        kaEnabled = true
        logger?("[KeepAlive] Enabled. App will stay alive in background.")
    } catch {
        logger?("[KeepAlive] Audio player failed: \(error)")
    }
}

private func kaWavURL() -> URL {
    let docs = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    )[0]
    return docs.appendingPathComponent("silent.wav")
}

private func makeSilentWav(at url: URL) {
    let sampleRate = 44100
    let duration = 1
    let numSamples = sampleRate * duration

    var wavData = Data()

    let byteRate = sampleRate * 2
    let blockAlign: UInt16 = 2
    let dataSize = numSamples * 2
    let chunkSize = 36 + dataSize

    func append<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            wavData.append(contentsOf: bytes)
        }
    }

    wavData.append("RIFF".data(using: .ascii)!)
    append(UInt32(chunkSize))
    wavData.append("WAVE".data(using: .ascii)!)

    wavData.append("fmt ".data(using: .ascii)!)
    append(UInt32(16))
    append(UInt16(1))
    append(UInt16(1))
    append(UInt32(sampleRate))
    append(UInt32(byteRate))
    append(blockAlign)
    append(UInt16(16))

    wavData.append("data".data(using: .ascii)!)
    append(UInt32(dataSize))

    wavData.append(Data(count: dataSize))

    try? wavData.write(to: url)
}
