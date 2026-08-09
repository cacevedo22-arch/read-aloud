import Foundation
import Capacitor
import SherpaOnnxC

/// Speaks text on the device with Kokoro, via sherpa-onnx.
///
/// The PC-server build sent every block over HTTP to a Python process. Here the
/// same block is synthesized locally and written to a .wav in Caches; the web
/// layer then plays it through the same two <audio> elements as before.
@objc(SherpaTtsPlugin)
public class SherpaTtsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SherpaTtsPlugin"
    public let jsName = "SherpaTts"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "synthesize", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "info", returnType: CAPPluginReturnPromise)
    ]

    // Model load takes seconds and the engine is not thread-safe, so keep one
    // instance and serialize every call onto a single queue.
    private var tts: OpaquePointer?
    private var loadError: String?
    private let queue = DispatchQueue(label: "sherpa-tts", qos: .userInitiated)

    private var modelDir: URL {
        Bundle.main.resourceURL!.appendingPathComponent("public/model")
    }

    private var cacheDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("tts", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Build the engine once. Returns false and sets loadError if files are missing.
    private func ensureLoaded() -> Bool {
        if tts != nil { return true }
        if loadError != nil { return false }

        let dir = modelDir
        let model = dir.appendingPathComponent("model.onnx").path
        let voices = dir.appendingPathComponent("voices.bin").path
        let tokens = dir.appendingPathComponent("tokens.txt").path
        let dataDir = dir.appendingPathComponent("espeak-ng-data").path
        let lexicon = dir.appendingPathComponent("lexicon-us-en.txt").path

        let fm = FileManager.default
        for p in [model, voices, tokens] where !fm.fileExists(atPath: p) {
            loadError = "missing \((p as NSString).lastPathComponent) in app bundle"
            return false
        }

        // Every const char* must outlive the C call, so hold the buffers here.
        return model.withCString { cModel in
        voices.withCString { cVoices in
        tokens.withCString { cTokens in
        dataDir.withCString { cData in
        lexicon.withCString { cLex in
        "".withCString { cEmpty in
            var kokoro = SherpaOnnxOfflineTtsKokoroModelConfig()
            kokoro.model = cModel
            kokoro.voices = cVoices
            kokoro.tokens = cTokens
            kokoro.data_dir = cData
            kokoro.length_scale = 1.0
            kokoro.dict_dir = cEmpty
            kokoro.lexicon = fm.fileExists(atPath: lexicon) ? cLex : cEmpty
            kokoro.lang = cEmpty

            var modelConfig = SherpaOnnxOfflineTtsModelConfig()
            modelConfig.kokoro = kokoro
            modelConfig.num_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
            modelConfig.debug = 0
            modelConfig.provider = cEmpty

            var config = SherpaOnnxOfflineTtsConfig()
            config.model = modelConfig
            config.rule_fsts = cEmpty
            config.rule_fars = cEmpty
            config.max_num_sentences = 1
            config.silence_scale = 0.2

            // SherpaOnnxOfflineTts is an opaque C struct, so Swift already
            // hands this back as an OpaquePointer - no cast needed.
            tts = withUnsafePointer(to: &config) { SherpaOnnxCreateOfflineTts($0) }
            if tts == nil { loadError = "sherpa-onnx refused to build the model" }
            return tts != nil
        }}}}}}
    }

    @objc func info(_ call: CAPPluginCall) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let ok = self.ensureLoaded()
            call.resolve([
                "ready": ok,
                "error": self.loadError ?? "",
                "speakers": ok ? Int(SherpaOnnxOfflineTtsNumSpeakers(self.tts)) : 0,
                "sampleRate": ok ? Int(SherpaOnnxOfflineTtsSampleRate(self.tts)) : 0,
                "modelDir": self.modelDir.path
            ])
        }
    }

    @objc func synthesize(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        let sid = Int32(call.getInt("sid") ?? 16)          // 16 = am_michael
        let speed = Float(call.getDouble("speed") ?? 1.0)

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            call.reject("empty text")
            return
        }

        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.ensureLoaded(), let engine = self.tts else {
                call.reject(self.loadError ?? "model not loaded")
                return
            }

            // Same text, voice and speed must map to the same file, so repeats
            // and re-reads are instant rather than re-synthesized.
            let key = "\(sid)-\(speed)-\(text)".data(using: .utf8)!
            let name = String(format: "%08x-%d", key.hashValue & 0x7fffffff, text.count)
            let out = self.cacheDir.appendingPathComponent("\(name).wav")

            if FileManager.default.fileExists(atPath: out.path) {
                call.resolve(["path": out.path, "cached": true])
                return
            }

            var gen = SherpaOnnxGenerationConfig()
            gen.silence_scale = 0.2
            gen.speed = speed
            gen.sid = sid
            gen.num_steps = 0

            let audio: UnsafePointer<SherpaOnnxGeneratedAudio>? = text.withCString { cText in
                withUnsafePointer(to: &gen) { cGen in
                    SherpaOnnxOfflineTtsGenerateWithConfig(engine, cText, cGen, nil, nil)
                }
            }
            guard let audio = audio, audio.pointee.n > 0 else {
                call.reject("synthesis produced no audio")
                return
            }
            defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

            let wrote = out.path.withCString { cPath in
                SherpaOnnxWriteWave(audio.pointee.samples, audio.pointee.n,
                                    audio.pointee.sample_rate, cPath)
            }
            if wrote != 1 {
                call.reject("could not write \(out.lastPathComponent)")
                return
            }

            call.resolve([
                "path": out.path,
                "cached": false,
                "seconds": Double(audio.pointee.n) / Double(audio.pointee.sample_rate)
            ])
        }
    }
}
