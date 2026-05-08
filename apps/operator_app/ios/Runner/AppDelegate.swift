import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let screenAwakeChannel = FlutterMethodChannel(
        name: "operator_app/screen_awake",
        binaryMessenger: controller.binaryMessenger
      )
      screenAwakeChannel.setMethodCallHandler { call, result in
        guard call.method == "setKeepScreenOn" else {
          result(FlutterMethodNotImplemented)
          return
        }

        let arguments = call.arguments as? [String: Any]
        let enabled = arguments?["enabled"] as? Bool ?? false
        UIApplication.shared.isIdleTimerDisabled = enabled
        result(nil)
      }

      let phoneChannel = FlutterMethodChannel(
        name: "operator_app/phone",
        binaryMessenger: controller.binaryMessenger
      )
      phoneChannel.setMethodCallHandler { call, result in
        guard call.method == "dial" else {
          result(FlutterMethodNotImplemented)
          return
        }

        let arguments = call.arguments as? [String: Any]
        let phone = (arguments?["phone"] as? String ?? "").trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        guard !phone.isEmpty,
              let encoded = phone.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
              ),
              let url = URL(string: "tel:\(encoded)"),
              UIApplication.shared.canOpenURL(url) else {
          result(false)
          return
        }

        UIApplication.shared.open(url) { success in
          result(success)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
