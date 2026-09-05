import re

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "r") as f:
    content = f.read()

content = re.sub(
    r"public enum RunType {",
    r"public enum RunType: Equatable {",
    content
)

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "w") as f:
    f.write(content)
