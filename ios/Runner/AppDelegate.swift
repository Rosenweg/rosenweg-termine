import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Abfrage im Hintergrund (rosenweg_basis HintergrundAbfrage): BGAppRefreshTask,
    // Kennung auch in Info.plist (BGTaskSchedulerPermittedIdentifiers). iOS entscheidet, wann.
    WorkmanagerPlugin.setPluginRegistrantCallback { (registry: FlutterPluginRegistry) in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "ch.rosenweg4303.termine.abfrage", earliestBeginInSeconds: 900)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
