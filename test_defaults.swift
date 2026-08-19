import Foundation
UserDefaults.standard.set(true, forKey: "useMetricSystem")
UserDefaults.standard.set(1.5, forKey: "minimumRunDistance")
print(UserDefaults.standard.bool(forKey: "useMetricSystem"))
print(UserDefaults.standard.double(forKey: "minimumRunDistance"))
let useMetricSystem = UserDefaults.standard.object(forKey: "useMetricSystem") as? Bool ?? true
let minimumRunDistance = UserDefaults.standard.object(forKey: "minimumRunDistance") as? Double ?? 1.0
print(useMetricSystem, minimumRunDistance)
