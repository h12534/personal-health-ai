// OCR stays local; stdout is consumed privately by the safety checker.
import Foundation
import Vision

do {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(domain: "SyntheticUIReview", code: 1)
    }
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    var texts = [String]()
    for languages in [["zh-Hans", "en-US"], ["en-US"]] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = try request.supportedRecognitionLanguages()
        guard languages.allSatisfy({ supported.contains($0) }) else {
            throw NSError(domain: "SyntheticUIReview", code: 2)
        }
        request.recognitionLanguages = languages
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        guard let observations = request.results, !observations.isEmpty else {
            throw NSError(domain: "SyntheticUIReview", code: 3)
        }
        texts.append(contentsOf: observations.compactMap {
            $0.topCandidates(1).first?.string
        })
    }
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: texts))
} catch {
    // Never expose a path, recognized secret, or raw system error.
    FileHandle.standardError.write(Data("OCR_CHECK_UNAVAILABLE\n".utf8))
    exit(1)
}
