import Foundation

/// Builds a tiny silent 16-bit PCM WAV file in memory, so no audio asset is needed.
enum SilentAudio {
    static func wavData(seconds: Double = 1, sampleRate: Int = 8000) -> Data {
        let numSamples = max(1, Int(Double(sampleRate) * seconds))
        let bitsPerSample = 16
        let channels = 1
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = numSamples * blockAlign

        var d = Data()
        func append(_ s: String) { d.append(s.data(using: .ascii)!) }
        func append32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func append16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }

        append("RIFF"); append32(36 + dataSize); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(channels)
        append32(sampleRate); append32(byteRate); append16(blockAlign); append16(bitsPerSample)
        append("data"); append32(dataSize)
        d.append(Data(count: dataSize))
        return d
    }
}
