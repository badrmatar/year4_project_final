import Flutter
import UIKit
import GoogleMaps
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate {
  private var locationManager: CLLocationManager?
  private var methodChannel: FlutterMethodChannel?
  private var backgroundLocationTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Google Maps SDK
    GMSServices.provideAPIKey("AIzaSyBffijFTKZIwz_Psp8FpXeXhyWj23G7VWo")

    // Set up method channel for communication with Flutter
    let controller = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(
      name: "com.duorun.location/background",
      binaryMessenger: controller.binaryMessenger
    )

    // Handle method calls from Flutter
    methodChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }

      switch call.method {
      case "startBackgroundLocationUpdates":
        self.setupBackgroundLocationCapabilities()
        result(true)
      case "stopBackgroundLocationUpdates":
        self.stopBackgroundLocationUpdates()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Register for location updates
    setupBackgroundLocationCapabilities()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupBackgroundLocationCapabilities() {
    // Initialize the location manager if it doesn't exist
    if locationManager == nil {
      locationManager = CLLocationManager()
      locationManager?.delegate = self

      // Configure for background updates
      locationManager?.allowsBackgroundLocationUpdates = true
      locationManager?.pausesLocationUpdatesAutomatically = false

      // Use best accuracy for running application
      locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation

      // Set activity type to fitness for better battery performance
      locationManager?.activityType = .fitness

      // Display the location indicator when using location in the background
      locationManager?.showsBackgroundLocationIndicator = true

      // Start standard location services
      locationManager?.startUpdatingLocation()

      // Also monitor for significant location changes as a fallback
      locationManager?.startMonitoringSignificantLocationChanges()
    }

    print("Background location capabilities set up")
  }

  private func stopBackgroundLocationUpdates() {
    locationManager?.stopUpdatingLocation()
    locationManager?.stopMonitoringSignificantLocationChanges()
    print("Background location updates stopped")
  }

  // Handle background app refresh
  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    // Start a background task to handle location updates
    backgroundLocationTask = UIApplication.shared.beginBackgroundTask { [weak self] in
      guard let self = self else { return }
      if self.backgroundLocationTask != .invalid {
        UIApplication.shared.endBackgroundTask(self.backgroundLocationTask)
        self.backgroundLocationTask = .invalid
      }
    }

    // Make sure we're still tracking location
    if CLLocationManager.locationServicesEnabled() {
      completionHandler(.newData)
    } else {
      completionHandler(.noData)
    }
  }

  // MARK: - CLLocationManagerDelegate

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // This delegate method is called when new locations are available
    guard let location = locations.last else { return }

    // Check if the location is recent
    let howRecent = location.timestamp.timeIntervalSinceNow
    if abs(howRecent) < 5.0 {
      // Only process recent locations
      let coordinate = location.coordinate
      let accuracy = location.horizontalAccuracy

      print("Location update from iOS native: \(coordinate.latitude), \(coordinate.longitude), accuracy: \(accuracy)")

      // If we have an active method channel, send the data back to Flutter
      if let channel = methodChannel {
        let locationData: [String: Any] = [
          "latitude": coordinate.latitude,
          "longitude": coordinate.longitude,
          "accuracy": accuracy,
          "timestamp": location.timestamp.timeIntervalSince1970 * 1000, // to milliseconds
          "altitude": location.altitude,
          "speed": location.speed >= 0 ? location.speed : 0, // Avoid negative speed values
          "speedAccuracy": location.speedAccuracy >= 0 ? location.speedAccuracy : 0,
        ]

        channel.invokeMethod("locationUpdate", arguments: locationData)
      }
    }

    // If we have a background task, extend it
    if backgroundLocationTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundLocationTask)
      backgroundLocationTask = .invalid
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("Location manager failed with error: \(error.localizedDescription)")

    // Send error to Flutter
    if let channel = methodChannel {
      channel.invokeMethod("locationError", arguments: ["message": error.localizedDescription])
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    var status = "unknown"

    if #available(iOS 14.0, *) {
      switch manager.authorizationStatus {
      case .notDetermined:
        status = "notDetermined"
      case .restricted:
        status = "restricted"
      case .denied:
        status = "denied"
      case .authorizedAlways:
        status = "authorizedAlways"
      case .authorizedWhenInUse:
        status = "authorizedWhenInUse"
      @unknown default:
        status = "unknown"
      }
    } else {
      switch CLLocationManager.authorizationStatus() {
      case .notDetermined:
        status = "notDetermined"
      case .restricted:
        status = "restricted"
      case .denied:
        status = "denied"
      case .authorizedAlways:
        status = "authorizedAlways"
      case .authorizedWhenInUse:
        status = "authorizedWhenInUse"
      @unknown default:
        status = "unknown"
      }
    }

    // Send authorization status to Flutter
    if let channel = methodChannel {
      channel.invokeMethod("authorizationStatus", arguments: ["status": status])
    }
  }
}