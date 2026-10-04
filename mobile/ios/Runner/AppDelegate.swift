import Flutter
import HealthKit
import UIKit
import UserNotifications
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
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let capabilities = FlutterMethodChannel(
      name: "personal_health_os/capabilities",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    capabilities.setMethodCallHandler { call, result in
      guard call.method == "healthKitAvailable" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(Self.canUseHealthKit())
    }
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

  private static func canUseHealthKit() -> Bool {
    guard HKHealthStore.isHealthDataAvailable() else { return false }
    guard Bundle.main.object(forInfoDictionaryKey: "AppDistribution") as? String
      == "personal_sideload" else { return true }
    if Bundle.main.object(forInfoDictionaryKey: "PersonalSideloadFree") as? String == "true" {
      return false
    }
    // Re-signers can omit capabilities. Fail closed before invoking the plugin.
    // This checks profile eligibility, not the user's private read permissions.
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      let data = try? Data(contentsOf: url), data.count <= 4 * 1024 * 1024,
      let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
      let plist = try? PropertyListSerialization.propertyList(
        from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil
      ) as? [String: Any],
      let entitlements = plist["Entitlements"] as? [String: Any]
    else { return false }
    return entitlements["com.apple.developer.healthkit"] as? Bool == true
      && signedHealthKitEntitlement()
  }

  private static func signedHealthKitEntitlement() -> Bool {
    // A profile can allow HealthKit even when a re-signer strips it from the
    // executable. Read our own standard Mach-O signature; no private API and
    // no attempt to create/change/bypass a signature. Unknown formats fail shut.
    guard let url = Bundle.main.executableURL,
      let data = try? Data(contentsOf: url, options: .mappedIfSafe)
    else { return false }
    func word(_ offset: Int, little: Bool = false) -> UInt32? {
      guard offset >= 0, offset + 4 <= data.count else { return nil }
      var value: UInt32 = 0
      for index in 0..<4 {
        let shift = little ? index * 8 : (3 - index) * 8
        value |= UInt32(data[offset + index]) << UInt32(shift)
      }
      return value
    }
    guard word(0, little: true) == 0xfeedfacf,
      let count = word(16, little: true), count <= 4096,
      let commandSize = word(20, little: true), Int(commandSize) <= data.count - 32
    else { return false }
    var cursor = 32
    for _ in 0..<Int(count) {
      guard cursor + 8 <= 32 + Int(commandSize),
        let command = word(cursor, little: true),
        let size = word(cursor + 4, little: true), size >= 8,
        cursor + Int(size) <= 32 + Int(commandSize)
      else { return false }
      if command == 0x1d { // LC_CODE_SIGNATURE
        guard size >= 16, let offset = word(cursor + 8, little: true),
          let length = word(cursor + 12, little: true), length >= 12,
          Int(offset) + Int(length) <= data.count
        else { return false }
        let start = Int(offset)
        let end = start + Int(length)
        guard word(start) == 0xfade0cc0, let entries = word(start + 8),
          entries <= 128, start + 12 + Int(entries) * 8 <= end
        else { return false }
        for index in 0..<Int(entries) {
          let item = start + 12 + index * 8
          guard let slot = word(item), let relative = word(item + 4),
            Int(relative) <= Int(length) - 8
          else { return false }
          if slot != 5 { continue } // CSSLOT_ENTITLEMENTS (XML)
          let blob = start + Int(relative)
          guard word(blob) == 0xfade7171, let blobSize = word(blob + 4),
            blobSize >= 8, blob + Int(blobSize) <= end,
            let entitlements = try? PropertyListSerialization.propertyList(
              from: data.subdata(in: (blob + 8)..<(blob + Int(blobSize))),
              options: [], format: nil
            ) as? [String: Any]
          else { return false }
          return entitlements["com.apple.developer.healthkit"] as? Bool == true
        }
        return false // DER-only/unknown envelopes are conservatively manual.
      }
      cursor += Int(size)
    }
    return false
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
