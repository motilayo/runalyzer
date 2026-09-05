import re

with open("RunalyzerTests/RunalyzerTests.swift", "r") as f:
    content = f.read()

# Fix HKWorkout initializer deprecation
content = re.sub(
    r"let workout = HKWorkout\(activityType: \.running, start: start, end: end\)",
    r"let workout = HKWorkout(activityType: .running, start: start, end: end, duration: end.timeIntervalSince(start), totalEnergyBurned: nil, totalDistance: nil, device: nil, metadata: nil)",
    content
)

with open("RunalyzerTests/RunalyzerTests.swift", "w") as f:
    f.write(content)
