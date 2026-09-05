import re

with open("RunalyzerTests/RunalyzerTests.swift", "r") as f:
    content = f.read()

content = re.sub(
    r"@testable import Runalyzer",
    r"@testable import Runalyzer\nimport Foundation",
    content
)

with open("RunalyzerTests/RunalyzerTests.swift", "w") as f:
    f.write(content)
