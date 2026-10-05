// OCR stays local; stdout is consumed privately by the safety checker.
import Foundation
import Vision

do {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(domain: "SyntheticUIReview", code: 1)
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    var rows = [[String: Any]]()
    for (pass, languages) in [("chinese", ["zh-Hans"]), ("english", ["en-US"])] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = try request.supportedRecognitionLanguages()
        guard languages.allSatisfy({ supported.contains($0) }) else {
            throw NSError(domain: "SyntheticUIReview", code: 2)
        }
        request.recognitionLanguages = languages
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        guard let observations = request.results else {
            throw NSError(domain: "SyntheticUIReview", code: 3)
        }
        for observation in observations {
            guard let text = observation.topCandidates(1).first?.string else {
                throw NSError(domain: "SyntheticUIReview", code: 4)
            }
            let box = observation.boundingBox
            rows.append([
                "text": text,
                "language_pass": pass,
                "bounds": [box.origin.x, box.origin.y, box.size.width, box.size.height]
            ])
        }
    }
    guard !rows.isEmpty else {
        throw NSError(domain: "SyntheticUIReview", code: 5)
    }
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rows))
} catch {
    // Never expose a path, recognized secret, or raw system error.
    FileHandle.standardError.write(Data("OCR_CHECK_UNAVAILABLE\n".utf8))
    exit(1)
}
