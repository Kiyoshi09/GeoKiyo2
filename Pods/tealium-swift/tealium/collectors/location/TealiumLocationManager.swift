//
//  TealiumLocationManager.swift
//  tealium-swift
//
//  Copyright © 2019 Tealium. All rights reserved.
//

#if os(iOS) && !targetEnvironment(macCatalyst)
import CoreLocation
import Foundation
#if location
import TealiumCore
#endif

public class TealiumLocationManager: NSObject, CLLocationManagerDelegate, TealiumLocationManagerProtocol {

    var config: TealiumConfig
    var logger: TealiumLoggerProtocol? {
        config.logger
    }
    var locationManager: LocationManagerProtocol
    var geofences = [Geofence]()
    weak var locationDelegate: LocationDelegate?
    var didEnterRegionWorking = false
    public var locationAccuracy: String = LocationKey.highAccuracy
    private var _lastLocation: CLLocation?

    init(config: TealiumConfig,
         bundle: Bundle = Bundle.main,
         locationDelegate: LocationDelegate? = nil,
         locationManager: LocationManagerProtocol = CLLocationManager()) {
        self.config = config
        self.locationDelegate = locationDelegate
        self.locationManager = locationManager
        self.locationAccuracy = config.useHighAccuracy ? LocationKey.highAccuracy : LocationKey.lowAccuracy

        super.init()

        if let locationConfig = config.initializeGeofenceDataFrom {
            switch locationConfig {
            case .localFile(let file):
                geofences = GeofenceData(file: file, bundle: bundle, logger: config.logger)?.geofences ?? [Geofence]()
            case .customUrl(let url):
                geofences = GeofenceData(url: url, logger: config.logger)?.geofences ?? [Geofence]()
            default:
                geofences = GeofenceData(url: geofencesUrl, logger: config.logger)?.geofences ?? [Geofence]()
            }
        }

        self.locationManager.distanceFilter = config.updateDistance
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = CLLocationAccuracy(config.desiredAccuracy)

        clearMonitoredGeofences()
    }

    /// Builds a URL from a Tealium config pointing to a hosted JSON file on the Tealium DLE
    var geofencesUrl: String {
        return "\(LocationKey.dleBaseUrl)\(config.account)/\(config.profile)/\(LocationKey.fileName).json"
    }

    /// - Returns: `Bool` Whether or not the user has authorized location tracking/updates
    public var isAuthorized: Bool {
        type(of: locationManager).self.authorizationStatus() == .authorizedAlways ||
            type(of: locationManager).self.authorizationStatus() == .authorizedWhenInUse
    }

    /// - Returns: `Bool` Whether or not the user has allowed "Precise" location tracking/updates
    @available(iOS 14.0, *)
    public var isFullAccuracy: Bool {
        return locationManager.accuracyAuthorization == .fullAccuracy
    }

    /// Gets the user's last known location
    ///
    /// - returns: `CLLocation ` location object
    public var lastLocation: CLLocation? {
        get {
            guard isAuthorized else {
                return nil
            }
            return _lastLocation
        }
        set {
            if let newValue = newValue {
                _lastLocation = newValue
            }
        }
    }

    /// Prompts the user to enable permission for location servies
    public func requestAuthorization() {
        let authorizationStatus = type(of: locationManager).self.authorizationStatus()

        if authorizationStatus != .authorizedAlways {
            locationManager.requestAlwaysAuthorization()
        }

        if  authorizationStatus != .authorizedWhenInUse {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    /// Automatically request temporary full accuracy if precise accuracy is disabled.
    ///
    /// - Parameter purposeKey: `String` A key in the `NSLocationTemporaryUsageDescriptionDictionary` dictionary of the app’s `Info.plist` file.
    @available(iOS 14.0, *)
    public func requestTemporaryFullAccuracyAuthorization(purposeKey: String) {
        guard isAuthorized else {
            return
        }
        locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey) { [weak self] error in
            if let self = self,
               let error = error as? CLError {
                if error.code == .denied {
                    self.logError(message: "🌎🌎 Temporary Full Authorization Denied 🌎🌎")
                } else {
                    self.logError(message: "🌎🌎 Error Requesting Temporary Full Authorization: \(error) 🌎🌎")
                }

            }
        }
    }

    /// Enables regular updates of location data through the location client
    /// Update frequency is dependant on config.useHighAccuracy, a parameter passed on initialization of this class.
    public func startLocationUpdates() {
        guard isAuthorized else {
            logInfo(message: "🌎🌎 Location Updates Service Not Enabled 🌎🌎")
            return
        }
        guard !config.useHighAccuracy,
              CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            locationManager.startUpdatingLocation()
            logInfo(message: "🌎🌎 Starting Location Updates With Frequent Monitoring 🌎🌎")
            
            // Added by Kiyoshi
            let locManager: CLLocationManager = locationManager as! CLLocationManager
            locManager.allowsBackgroundLocationUpdates = true
            //
            
            return
        }
        locationManager.startMonitoringSignificantLocationChanges()
        logInfo(message: "🌎🌎 Starting Location Updates With Significant Location Changes Only 🌎🌎")
        
//         //Added by Kiyoshi
        let locManager: CLLocationManager = locationManager as! CLLocationManager
        locManager.allowsBackgroundLocationUpdates = true
        
    }

    /// Stops the updating of location data through the location client.
    public func stopLocationUpdates() {
        guard isAuthorized else {
            return
        }
        locationManager.stopUpdatingLocation()
        logInfo(message: "🌎🌎 Location Updates Stopped 🌎🌎")
    }

    /// CLLocationManagerDelegate method
    /// Updates a member variable containing the most recent device location alongisde
    /// updating the monitored geofences based on the users last location. (Dynamic Geofencing)
    ///
    /// - parameter manager: `CLLocationManager` instance
    /// - parameter locations: `[CLLocation]` array of recent locations, includes most recent
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let lastLocation = locations.last {
            self.lastLocation = lastLocation
        }
        logInfo(message: "🌎🌎 Location updated: \(String(describing: lastLocation?.coordinate)) 🌎🌎")
        geofences.regions.forEach {
            let geofenceLocation = CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude)

            guard let distance = lastLocation?.distance(from: geofenceLocation),
                  distance.isLess(than: config.updateDistance) else {
                
                print("[0630-1] Stop Monitoring.. location=\(lastLocation?.coordinate.latitude),\(lastLocation?.coordinate.longitude)")
                print("[0630-1] Stop Monitoring.. distance=\(lastLocation?.distance(from: geofenceLocation))")
                
                stopMonitoring(geofence: $0)
                return
            }
            
            print("[0630-1] /// Start Monitoring /// location=\(lastLocation?.coordinate.latitude),\(lastLocation?.coordinate.longitude)")
            print("[0630-1] /// Start Monitoring /// distance=\(lastLocation?.distance(from: geofenceLocation))")
            
            startMonitoring(geofence: $0)
        }
    }

    /// CLLocationManagerDelegate method
    /// If the location client encounters an error, location updates are stopped
    ///
    /// - parameter manager: `CLLocationManager` instance
    /// - parameter error: `error` an error that has occured
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError,
           error.code == .denied {
            logError(message: "🌎🌎 Location Authorization Denied 🌎🌎")
            locationManager.stopUpdatingLocation()
        } else {
            logError(message: "🌎🌎 An Error Has Occured: \(String(describing: error.localizedDescription)) 🌎🌎")
        }
    }

    /// CLLocationManagerDelegate method
    /// Calls for the sending of a Tealium tracking calls on geofence enter and exit event
    ///
    /// - parameter manager: `CLLocationManager` instance
    /// - parameter state: `CLRegionState` state of the device with reference to a region.
    /// - parameter region: `CLRegion` that was entered
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .inside && region.notifyOnEntry {
            sendGeofenceTrackingEvent(region: region, triggeredTransition: LocationKey.entered)
        } else if state == .outside && region.notifyOnExit {
            sendGeofenceTrackingEvent(region: region, triggeredTransition: LocationKey.exited)
        }
    }

    /// `CLLocationManagerDelegate` method
    /// Calls for the sending of a Tealium tracking calls on geofence enter and exit event. Deprecated in iOS 14
    ///
    /// - parameter manager: `CLLocationManager` instance
    /// - parameter status: `CLAuthorizationStatus` authorization state of the application.
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        startLocationUpdates()
    }

    /// `CLLocationManagerDelegate` method
    /// Calls for the sending of a Tealium tracking calls on geofence enter and exit event. Available in iOS 14 only
    ///
    /// - parameter manager: `CLLocationManager` instance
    @available(iOS 14.0, *)
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startLocationUpdates()
    }

    /// Sends a Tealium tracking event, appending geofence data to the track.
    ///
    /// - parameter region: `CLRegion` that was entered
    /// - parameter triggeredTransition: `String` Type of transition that occured
    public func sendGeofenceTrackingEvent(region: CLRegion, triggeredTransition: String) {
        var data = [String: Any]()
        data[LocationKey.geofenceName] = "\(region.identifier)"
        data[LocationKey.geofenceTransition] = "\(triggeredTransition)"
        data[TealiumKey.event] = triggeredTransition

        if let lastLocation = lastLocation {
            data[LocationKey.deviceLatitude] = "\(lastLocation.coordinate.latitude)"
            data[LocationKey.deviceLongitude] = "\(lastLocation.coordinate.longitude)"
            data[LocationKey.timestamp] = "\(lastLocation.timestamp)"
            data[LocationKey.speed] = "\(lastLocation.speed)"
            data[LocationKey.accuracy] = locationAccuracy
            data[LocationKey.accuracyExtended] = config.desiredAccuracy.rawValue
        }

        if triggeredTransition == LocationKey.exited {
            print("/////// [tealium_event=geofence_exited] ////////")
            
            if #available(iOS 10.0, *) {
                sendLocalPushNotification("Exited", "Tealium Geofence", "")
            } else {
                // Fallback on earlier versions
            }
            
            locationDelegate?.didExitGeofence(data)
        } else if triggeredTransition == LocationKey.entered {
            print("/////// [0630-1][geofence_entered : tealium_event=geofence_entered] ////////")
            
            // デバッグ
            if let lastLocation = lastLocation {
                
                print("[0630-1][geofence_entered : coordinate] \(lastLocation.coordinate.latitude), \(lastLocation.coordinate.longitude)")
                
                geofences.regions.forEach {
                    let geofenceLocation = CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude)
                    
                    print("[0630-1][geofence_entered : distance from center] \(lastLocation.distance(from: geofenceLocation))")
                }
            }
            //
            
            
            if #available(iOS 10.0, *) {
                sendLocalPushNotification("Entered", "Tealium Geofence", "")
            } else {
                // Fallback on earlier versions
            }
            
            locationDelegate?.didEnterGeofence(data)
        }
    }

    /// Adds geofences to the Location Client to be monitored
    ///
    /// - parameter geofences: `[CLCircularRegion]` Geofences to be added
    public func startMonitoring(_ geofences: [CLCircularRegion]) {
        if geofences.capacity == 0 {
            return
        }

        geofences.forEach {
            startMonitoring(geofence: $0)
        }
    }

    /// Adds geofences to the Location Client to be monitored
    ///
    /// - parameter geofence: `CLCircularRegion` Geofence to be added
    public func startMonitoring(geofence: CLCircularRegion) {
        if !locationManager.monitoredRegions.contains(geofence) {
            locationManager.startMonitoring(for: geofence)
            logInfo(message: "🌎🌎 \(geofence.identifier) Added to monitored client 🌎🌎")
        }
    }

    /// Removes geofences from being monitored by the Location Client
    ///
    /// - parameter geofences: `[CLCircularRegion]` Geofences to be removed
    public func stopMonitoring(_ geofences: [CLCircularRegion]) {
        if geofences.capacity == 0 {
            return
        }

        geofences.forEach {
            stopMonitoring(geofence: $0)
        }
    }

    /// Removes geofences from being monitored by the Location Client
    ///
    /// - parameter geofence: `CLCircularRegion` Geofence to be removed
    public func stopMonitoring(geofence: CLCircularRegion) {
        if locationManager.monitoredRegions.contains(geofence) {
            locationManager.stopMonitoring(for: geofence)
            logInfo(message: "🌎🌎 \(geofence.identifier) Removed from monitored client 🌎🌎")
        }
    }

    /// Returns the names of all the geofences that are currently being monitored
    ///
    /// - return: `[String]?` Array containing the names of monitored geofences
    public var monitoredGeofences: [String]? {
        guard isAuthorized else {
            return nil
        }
        return locationManager.monitoredRegions.map { $0.identifier }
    }

    /// Returns the names of all the created geofences (those currently being monitored and those that are not)
    ///
    /// - return: `[String]?` Array containing the names of all geofences
    public var createdGeofences: [String]? {
        guard isAuthorized else {
            return nil
        }
        return geofences.map { $0.name }
    }

    /// Removes all geofences that are currently being monitored from the Location Client
    public func clearMonitoredGeofences() {
        locationManager.monitoredRegions.forEach {
            locationManager.stopMonitoring(for: $0)
        }
    }

    /// Stops location updates, Removes all active geofences from being monitored,
    /// and resets the array of created geofences
    public func disable() {
        stopLocationUpdates()
        clearMonitoredGeofences()
        self.geofences = [Geofence]()
    }

    /// Logs errors about events occuring in the `TealiumLocation` module
    /// - Parameter message: `String` message to log to the console
    func logError(message: String) {
        let logRequest = TealiumLogRequest(title: "Tealium Location", message: message, info: nil, logLevel: .error, category: .general)
        logger?.log(logRequest)
    }

    /// Logs verbose information about events occuring in the `TealiumLocation` module
    /// - Parameter message: `String` message to log to the console
    func logInfo(message: String) {
        let logRequest = TealiumLogRequest(title: "Tealium Location", message: message, info: nil, logLevel: .debug, category: .general)
        logger?.log(logRequest)
    }
    
    /// Kiyoshi Added : Local Push
    
    @available(iOS 10.0, *)
    func sendLocalPushNotification(_ title: String, _ subtitle: String, _ body: String){
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "localPush", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

}

extension CLLocationAccuracy {
    init(_ accuracy: LocationAccuracy) {
        switch accuracy {
        case .bestForNavigation:
            self = kCLLocationAccuracyBestForNavigation
        case .best:
            self = kCLLocationAccuracyBest
        case .nearestTenMeters:
            self = kCLLocationAccuracyNearestTenMeters
        case .nearestHundredMeters:
            self = kCLLocationAccuracyHundredMeters
        case .reduced:
            if #available(iOS 14.0, *) {
                self = kCLLocationAccuracyReduced
            } else {
                self = kCLLocationAccuracyHundredMeters
            }
        case .withinOneKilometer:
            self = kCLLocationAccuracyKilometer
        case .withinThreeKilometers:
            self = kCLLocationAccuracyThreeKilometers
        }
    }
}

#endif
