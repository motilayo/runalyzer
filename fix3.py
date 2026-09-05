import re

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "r") as f:
    content = f.read()

content = re.sub(
    r"public class FramboiseEngine {",
    r"public class FramboiseEngine {\n\n    public init() {}\n",
    content
)

with open("Runalyzer/CoachingEngine/FramboiseEngine.swift", "w") as f:
    f.write(content)
