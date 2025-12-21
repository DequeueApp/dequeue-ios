//
//  DeviceService.swift
//  Dequeue
//
//  Manages unique device identification for sync
//

import Foundation

actor DeviceService {
    static let shared = DeviceService()

    private let deviceIdKey = "com.dequeue.deviceId"
    private var cachedDeviceId: String?

    private init() {}

    func getDeviceId() async -> String {
        if let cached = cachedDeviceId {
            return cached
        }

        if let stored = UserDefaults.standard.string(forKey: deviceIdKey) {
            cachedDeviceId = stored
            return stored
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        cachedDeviceId = newId
        return newId
    }

    func resetDeviceId() async -> String {
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        cachedDeviceId = newId
        return newId
    }
}
