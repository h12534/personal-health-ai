import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UIDocumentPickerDelegate
{
  private var documentPickerResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "personal_health_os/document_picker",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickPdf" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.presentPdfPicker(result: result)
    }
  }

  private func presentPdfPicker(result: @escaping FlutterResult) {
    guard documentPickerResult == nil else {
      result(FlutterError(code: "picker_busy", message: "文件选择器正在使用中。", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "picker_unavailable", message: "无法打开系统文件选择器。", details: nil))
      return
    }
    documentPickerResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf], asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let result = documentPickerResult else { return }
    documentPickerResult = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    let hasScopedAccess = url.startAccessingSecurityScopedResource()
    defer {
      if hasScopedAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }
    do {
      let data = try Data(contentsOf: url, options: .mappedIfSafe)
      result([
        "name": url.lastPathComponent,
        "bytes": FlutterStandardTypedData(bytes: data),
      ])
    } catch {
      result(
        FlutterError(
          code: "picker_read_failed",
          message: "无法读取所选 PDF。",
          details: nil
        )
      )
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    documentPickerResult?(nil)
    documentPickerResult = nil
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController
    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    return current
  }
}
