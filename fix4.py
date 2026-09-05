import re

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "r") as f:
    content = f.read()

content = re.sub(
    r"static func fetchMetricsConcurrently",
    r"public static func fetchMetricsConcurrently",
    content
)

content = re.sub(
    r"static func generateTimeBuckets",
    r"public static func generateTimeBuckets",
    content
)

content = re.sub(
    r"static func trimOutliers",
    r"public static func trimOutliers",
    content
)

content = re.sub(
    r"static func checkPaceVariance",
    r"public static func checkPaceVariance",
    content
)

content = re.sub(
    r"static func checkCadenceFading",
    r"public static func checkCadenceFading",
    content
)

content = re.sub(
    r"static func classifyRun",
    r"public static func classifyRun",
    content
)

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "w") as f:
    f.write(content)
