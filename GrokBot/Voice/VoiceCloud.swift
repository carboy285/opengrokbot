import Foundation

/// Optional cloud speech services. Keys come from the Keychain (see VoiceKeys); audio is sent only to the provider you pick.
enum VoiceCloud {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func transcribe(wav: Data, provider: VoiceProvider, key: String) async throws -> String {
        let endpoint: String, model: String
        switch provider {
        case .groq: endpoint = "https://api.groq.com/openai/v1/audio/transcriptions"; model = "whisper-large-v3-turbo"
        case .openAI: endpoint = "https://api.openai.com/v1/audio/transcriptions"; model = "whisper-1"
        case .elevenLabs: endpoint = "https://api.elevenlabs.io/v1/speech-to-text"; model = "scribe_v1"
        case .apple: throw Failure("Apple recognition runs on the device.")
        case .local: throw Failure("Local listening runs on this computer.")
        case .nvidiaNIM, .nvidiaCloud, .gemini: throw Failure("\(provider.title) is used for speaking only. Choose another provider for listening.")
        }
        guard let url = URL(string: endpoint) else { throw Failure("Invalid speech service address.") }
        let boundary = "voice-" + UUID().uuidString
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        if provider == .elevenLabs { request.setValue(key, forHTTPHeaderField: "xi-api-key") }
        else { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field(provider == .elevenLabs ? "model_id" : "model", model)
        if provider != .elevenLabs { field("response_format", "json") }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        let data = try await perform(request, provider: provider)
        let text = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["text"] as? String
        return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One shared session with a few open connections, so each spoken piece does not pay for a new TLS handshake.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 45
        return URLSession(configuration: configuration)
    }()

    /// Opens a connection to the speech provider before the first reply so the first sentence starts sooner. Failures are ignored.
    static func warmUp(_ provider: VoiceProvider) async {
        let host: String
        switch provider {
        case .openAI: host = "https://api.openai.com"
        case .groq: host = "https://api.groq.com"
        case .elevenLabs: host = "https://api.elevenlabs.io"
        case .gemini: host = VoiceSettings.geminiBaseURL
        default: return
        }
        guard let url = URL(string: host), url.scheme == "https" else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        _ = try? await session.data(for: request)
    }

    static func synthesize(text: String, provider: VoiceProvider, key: String) async throws -> Data {
        var request: URLRequest
        switch provider {
        case .openAI:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!, timeoutInterval: 45)
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "tts-1", "voice": "alloy", "input": text, "response_format": "mp3"])
        case .groq:
            // Groq's Orpheus voices: short requests, so replies are split before they get here (see maxSpeechCharacters).
            request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/speech")!, timeoutInterval: 30)
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "canopylabs/orpheus-v1-english", "voice": VoiceSettings.groqVoice, "input": text, "response_format": "wav"])
        case .elevenLabs:
            let id = VoiceSettings.elevenLabsVoiceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(id)?output_format=mp3_22050_32") else { throw Failure("The ElevenLabs voice ID looks invalid.") }
            request = URLRequest(url: url, timeoutInterval: 45)
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "model_id": "eleven_flash_v2_5"])
        case .nvidiaNIM:
            guard let url = VoiceSettings.nimSynthesizeURL(VoiceSettings.nimBaseURL) else { throw Failure("The NVIDIA NIM address in voice settings looks invalid. Use something like http://localhost:9000.") }
            request = URLRequest(url: url, timeoutInterval: 30)
            if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
            let boundary = "voice-" + UUID().uuidString
            request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
            var body = Data()
            for (name, value) in [("language", "en-US"), ("text", text), ("voice", VoiceSettings.nimVoice)] {
                body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            request.httpBody = body
        case .gemini:
            guard let url = VoiceSettings.geminiURL(base: VoiceSettings.geminiBaseURL, model: VoiceSettings.geminiModel) else { throw Failure("The Google AI Studio model name or address in voice settings looks invalid.") }
            request = URLRequest(url: url, timeoutInterval: 45)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["contents": [["parts": [["text": text]]]],
                                       "generationConfig": ["responseModalities": ["AUDIO"], "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": VoiceSettings.geminiVoice]]]]]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        case .nvidiaCloud:
            guard let url = VoiceSettings.nvidiaCloudURL(VoiceSettings.nvidiaCloudServer) else { throw Failure("The NVIDIA Cloud server address in voice settings looks invalid. Use something like grpc.nvcf.nvidia.com:443.") }
            guard VoiceSettings.isValidFunctionID(VoiceSettings.nvidiaCloudFunctionID) else { throw Failure("The NVIDIA Cloud function (model) ID in voice settings looks invalid.") }
            request = URLRequest(url: url, timeoutInterval: 30)
            request.setValue("application/grpc", forHTTPHeaderField: "Content-Type")
            request.setValue("trailers", forHTTPHeaderField: "TE")
            request.setValue("Bearer " + key, forHTTPHeaderField: "authorization")
            request.setValue(VoiceSettings.nvidiaCloudFunctionID.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "function-id")
            request.httpBody = RivaTTS.frame(RivaTTS.synthesizeRequest(text: text, voice: VoiceSettings.nvidiaCloudVoice))
        default: throw Failure("This provider can’t speak replies.")
        }
        request.httpMethod = "POST"
        do {
            let data = try await perform(request, provider: provider)
            switch provider {
            case .gemini: return try decodeGemini(data)
            case .nvidiaCloud: return try decodeNVIDIACloud(data)
            default: return data
            }
        } catch let error as URLError where provider == .nvidiaNIM {
            throw Failure("Couldn’t reach your NVIDIA NIM at \(VoiceSettings.nimBaseURL) (\(error.localizedDescription)). Is the container running?")
        } catch let error as URLError where provider == .nvidiaCloud || provider == .gemini {
            throw Failure("Couldn’t reach \(provider.title) (\(error.localizedDescription)). Check your connection and the address in voice settings.")
        }
    }

    private static func perform(_ request: URLRequest, provider: VoiceProvider) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure("No response from \(provider.title).") }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw Failure("\(provider.title) rejected the key. Check it in voice settings.")
            case 400 where provider == .gemini || provider == .nvidiaCloud: throw Failure("\(provider.title) rejected the request (400). Check the key, model or function ID, and address in voice settings.")
            case 429: throw Failure("\(provider.title) free quota or rate limit reached.")
            default: throw Failure("\(provider.title) returned an error (\(http.statusCode)).")
            }
        }
        return data
    }
}

/// Minimal Riva (NVIDIA speech) gRPC messages: just enough to ask for speech and read the audio back.
enum RivaTTS {
    static func varint(_ value: UInt64) -> [UInt8] {
        var out: [UInt8] = [], rest = value
        while rest >= 0x80 { out.append(UInt8(rest & 0x7F) | 0x80); rest >>= 7 }
        out.append(UInt8(rest)); return out
    }
    private static func field(_ number: Int, string: String) -> [UInt8] { let bytes = Array(string.utf8); return varint(UInt64(number << 3 | 2)) + varint(UInt64(bytes.count)) + bytes }
    private static func field(_ number: Int, int: Int) -> [UInt8] { varint(UInt64(number << 3)) + varint(UInt64(int)) }

    /// SynthesizeSpeechRequest: text (1), language_code (2), encoding (3, 1 = linear PCM), sample_rate_hz (4), voice_name (5).
    static func synthesizeRequest(text: String, language: String = "en-US", sampleRate: Int = 22_050, voice: String) -> Data {
        Data(field(1, string: text) + field(2, string: language) + field(3, int: 1) + field(4, int: sampleRate) + field(5, string: voice))
    }

    /// A gRPC message is one flag byte (0 = not compressed), a 4-byte big-endian length, then the protobuf.
    static func frame(_ message: Data) -> Data {
        var out = Data([0]); var length = UInt32(message.count).bigEndian
        out.append(Data(bytes: &length, count: 4)); out.append(message); return out
    }

    static func unframe(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 5, bytes[0] == 0 else { return nil }
        let length = Int(bytes[1]) << 24 | Int(bytes[2]) << 16 | Int(bytes[3]) << 8 | Int(bytes[4])
        guard length > 0, bytes.count >= 5 + length else { return nil }
        return Data(bytes[5..<(5 + length)])
    }

    /// SynthesizeSpeechResponse: the audio is field 1 (bytes).
    static func audio(fromResponse message: Data) -> Data? {
        let bytes = [UInt8](message); var index = 0
        func readVarint() -> UInt64? {
            var value: UInt64 = 0, shift: UInt64 = 0
            while index < bytes.count, shift < 64 { let byte = bytes[index]; index += 1; value |= UInt64(byte & 0x7F) << shift; if byte & 0x80 == 0 { return value }; shift += 7 }
            return nil
        }
        while index < bytes.count {
            guard let key = readVarint() else { return nil }
            switch key & 7 {
            case 0: guard readVarint() != nil else { return nil }
            case 1: index += 8
            case 5: index += 4
            case 2:
                guard let length = readVarint(), index + Int(length) <= bytes.count else { return nil }
                if key >> 3 == 1 { return Data(bytes[index..<(index + Int(length))]) }
                index += Int(length)
            default: return nil
            }
        }
        return nil
    }
}

extension VoiceCloud {
    /// Gemini answers with JSON whose first part carries base64 audio (raw 16-bit PCM, usually 24 kHz). Returns playable WAV.
    static func decodeGemini(_ data: Data) throws -> Data {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let inline = parts.compactMap({ $0["inlineData"] as? [String: Any] ?? $0["inline_data"] as? [String: Any] }).first,
              let encoded = inline["data"] as? String, let pcm = Data(base64Encoded: encoded), !pcm.isEmpty else {
            throw Failure("Google AI Studio returned no audio. Check the model name and that it supports speech.")
        }
        let mime = (inline["mimeType"] as? String) ?? (inline["mime_type"] as? String) ?? ""
        var rate = 24_000
        if let range = mime.range(of: "rate=[0-9]+", options: .regularExpression), let value = Int(mime[range].dropFirst(5)), (8_000...48_000).contains(value) { rate = value }
        return pcm.starts(with: Array("RIFF".utf8)) ? pcm : VoiceWAV.wrap(pcm: pcm, sampleRate: rate)
    }

    /// NVIDIA Cloud returns a gRPC frame around the protobuf response; the audio is raw PCM (or already WAV).
    static func decodeNVIDIACloud(_ data: Data, sampleRate: Int = 22_050) throws -> Data {
        guard let message = RivaTTS.unframe(data), let audio = RivaTTS.audio(fromResponse: message), !audio.isEmpty else {
            throw Failure("NVIDIA Cloud returned no audio. Check the API key, function ID and server address in voice settings.")
        }
        return audio.starts(with: Array("RIFF".utf8)) ? audio : VoiceWAV.wrap(pcm: audio, sampleRate: sampleRate)
    }
}
