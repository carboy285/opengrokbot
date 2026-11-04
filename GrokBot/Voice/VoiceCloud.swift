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
        case .nvidiaNIM: throw Failure("NVIDIA NIM is used for speaking only. Choose another provider for listening.")
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
            guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(id)?output_format=mp3_44100_64") else { throw Failure("The ElevenLabs voice ID looks invalid.") }
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
        default: throw Failure("This provider can’t speak replies.")
        }
        request.httpMethod = "POST"
        do { return try await perform(request, provider: provider) }
        catch let error as URLError where provider == .nvidiaNIM {
            throw Failure("Couldn’t reach your NVIDIA NIM at \(VoiceSettings.nimBaseURL) (\(error.localizedDescription)). Is the container running?")
        }
    }

    private static func perform(_ request: URLRequest, provider: VoiceProvider) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure("No response from \(provider.title).") }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw Failure("\(provider.title) rejected the key. Check it in voice settings.")
            case 429: throw Failure("\(provider.title) free quota or rate limit reached.")
            default: throw Failure("\(provider.title) returned an error (\(http.statusCode)).")
            }
        }
        return data
    }
}
