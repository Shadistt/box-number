import CoreML
import Vision
import UIKit
import Accelerate

/// Подписи вещей через SigLIP 2 (Apache-2.0): фото → вектор, сравнение с заранее посчитанными
/// векторами русских подписей (ml/labels_ru.txt). Модель грузится при первом снимке и живёт, пока
/// открыт экран места; выгружается по предупреждению о памяти.
final class ClipCaptioner: @unchecked Sendable {
    static let shared = ClipCaptioner()

    struct Candidate { let title: String; let score: Float }   // score — softmax по всем подписям

    private let queue = DispatchQueue(label: "co.boxnumber.clip", qos: .userInitiated)
    private var model: VNCoreMLModel?
    private var labels: [String] = []
    private var embeddings: [Float] = []    // N × dim, нормированные
    private var dim = 0
    private var logitScale: Float = 100
    private var loadFailed = false

    var isAvailable: Bool { Bundle.main.url(forResource: "SigLIP2Image", withExtension: "mlmodelc") != nil }

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.model = nil }
        }
    }

    func unload() { queue.async { self.model = nil } }

    private func loadIfNeeded() -> Bool {
        if model != nil { return true }
        if loadFailed { return false }
        guard let url = Bundle.main.url(forResource: "SigLIP2Image", withExtension: "mlmodelc"),
              let labelsURL = Bundle.main.url(forResource: "labels", withExtension: "json"),
              let embURL = Bundle.main.url(forResource: "label_embeddings", withExtension: "bin") else { loadFailed = true; return false }
        do {
            let cfg = MLModelConfiguration(); cfg.computeUnits = .all
            let ml = try MLModel(contentsOf: url, configuration: cfg)
            model = try VNCoreMLModel(for: ml)
            let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: labelsURL)) as? [String: Any]
            labels = meta?["labels"] as? [String] ?? []
            dim = meta?["dim"] as? Int ?? 768
            let data = try Data(contentsOf: embURL)
            embeddings = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            if let m = Bundle.main.url(forResource: "meta", withExtension: "json"),
               let j = try? JSONSerialization.jsonObject(with: Data(contentsOf: m)) as? [String: Any],
               let s = j["logit_scale"] as? Double { logitScale = Float(s) }
            guard embeddings.count == labels.count * dim else { loadFailed = true; model = nil; return false }
            return true
        } catch {
            print("ClipCaptioner load:", error); loadFailed = true; return false
        }
    }

    /// Топ-k подписей. Пусто — если модели нет или не вышло.
    func candidates(_ image: UIImage, top k: Int = 5) async -> [Candidate] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            queue.async { [self] in
                guard loadIfNeeded(), let model else { cont.resume(returning: []); return }
                let req = VNCoreMLRequest(model: model)
                req.imageCropAndScaleOption = .centerCrop
                let handler = VNImageRequestHandler(cgImage: cg, orientation: Captioner.cgOrientation(image.imageOrientation))
                do { try handler.perform([req]) } catch { cont.resume(returning: []); return }
                guard let obs = req.results?.first as? VNCoreMLFeatureValueObservation,
                      let arr = obs.featureValue.multiArrayValue else { cont.resume(returning: []); return }
                var v = [Float](repeating: 0, count: arr.count)
                for i in 0..<arr.count { v[i] = arr[i].floatValue }
                guard v.count == dim else { cont.resume(returning: []); return }
                // косинусы со всеми подписями
                let n = labels.count
                var sims = [Float](repeating: 0, count: n)
                embeddings.withUnsafeBufferPointer { e in
                    v.withUnsafeBufferPointer { q in
                        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(n), Int32(dim), 1, e.baseAddress, Int32(dim), q.baseAddress, 1, 0, &sims, 1)
                    }
                }
                // softmax с температурой модели → относительная уверенность
                var logits = sims.map { $0 * logitScale }
                let mx = logits.max() ?? 0
                logits = logits.map { exp($0 - mx) }
                let sum = logits.reduce(0, +)
                let probs = logits.map { $0 / sum }
                let order = probs.indices.sorted { probs[$0] > probs[$1] }.prefix(k)
                cont.resume(returning: order.map { Candidate(title: labels[$0], score: probs[$0]) })
            }
        }
    }
}
