import re

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "r") as f:
    content = f.read()

# Make models public
content = re.sub(
    r"struct RunMetrics {",
    r"public struct RunMetrics {",
    content
)

content = re.sub(
    r"struct Bucket: Equatable {",
    r"public struct Bucket: Equatable {",
    content
)

content = re.sub(
    r"enum RunType {",
    r"public enum RunType {",
    content
)

content = re.sub(
    r"class FramboiseEngine {",
    r"public class FramboiseEngine {",
    content
)

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "w") as f:
    f.write(content)
