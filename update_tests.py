import sys
import re

def update_test_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    # Update calculateRollingAverages to be async in tests as well
    content = re.sub(r'let baseline = try await engine\.calculateRollingAverages\(days: 7, to: targetDate\)',
                     r'let baseline = try await engine.calculateRollingAverages(days: 7, minimumDistance: 0, to: targetDate)', content)

    with open(filepath, 'w') as f:
        f.write(content)

update_test_file("RunalyzerTests/MacroQueryEngineTests.swift")
