import re

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "r") as f:
    content = f.read()

content = re.sub(
    r"public struct Bucket: Equatable {",
    r"public struct Bucket: Equatable {\n    public let date: Date\n    public let value: Double\n\n    public init(date: Date, value: Double) {\n        self.date = date\n        self.value = value\n    }\n",
    content
)

content = re.sub(
    r"public struct RunMetrics {",
    r"public struct RunMetrics {\n    public var heartRateBuckets: [Bucket] = []\n    public var cadenceBuckets: [Bucket] = []\n    public var paceBuckets: [Bucket] = []\n\n    public init(heartRateBuckets: [Bucket] = [], cadenceBuckets: [Bucket] = [], paceBuckets: [Bucket] = []) {\n        self.heartRateBuckets = heartRateBuckets\n        self.cadenceBuckets = cadenceBuckets\n        self.paceBuckets = paceBuckets\n    }\n",
    content
)

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "w") as f:
    f.write(content)
