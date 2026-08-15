import UIKit
import Flutter
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
  GeneratedPluginRegistrant.register(with: self)
      WorkmanagerPlugin.registerPeriodicTask(
        withIdentifier: "com.oscarspalk.lpp.notification",
        frequency: NSNumber(value: 20 * 60)
      )

      WorkmanagerPlugin.setPluginRegistrantCallback { registry in
              // Registry in this case is the FlutterEngine that is created in Workmanager's
              // performFetchWithCompletionHandler or BGAppRefreshTask.
              // This will make other plugins available during a background operation.
              GeneratedPluginRegistrant.register(with: registry)
          }
      
  return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
