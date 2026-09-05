import re

with open("Runalyzer.xcodeproj/project.pbxproj", "r") as f:
    content = f.read()

# Add FramboiseEngine.swift to PBXBuildFile
if "FramboiseEngine.swift" not in content:
    content = content.replace(
        "/* Runalyzer/CoachingEngine/CoachingEngine.swift in Sources */ = {isa = PBXBuildFile; fileRef = Z1X2C3V4B5N6M7L8K9J0H1G2 /* Runalyzer/CoachingEngine/CoachingEngine.swift */; };",
        "/* Runalyzer/CoachingEngine/CoachingEngine.swift in Sources */ = {isa = PBXBuildFile; fileRef = Z1X2C3V4B5N6M7L8K9J0H1G2 /* Runalyzer/CoachingEngine/CoachingEngine.swift */; };\n\t\tF1R2A3M4B5O6I7S8E9E0N1G2 /* FramboiseEngine.swift in Sources */ = {isa = PBXBuildFile; fileRef = F1R2A3M4B5O6I7S8E9E0N1G3 /* FramboiseEngine.swift */; };"
    )

    # Add to PBXFileReference
    content = content.replace(
        "/* Runalyzer/CoachingEngine/CoachingEngine.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Runalyzer/CoachingEngine/CoachingEngine.swift; sourceTree = SOURCE_ROOT; };",
        "/* Runalyzer/CoachingEngine/CoachingEngine.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Runalyzer/CoachingEngine/CoachingEngine.swift; sourceTree = SOURCE_ROOT; };\n\t\tF1R2A3M4B5O6I7S8E9E0N1G3 /* FramboiseEngine.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FramboiseEngine.swift; sourceTree = \"<group>\"; };"
    )

    # Add to PBXGroup CoachingEngine
    content = content.replace(
        "Z1X2C3V4B5N6M7L8K9J0H1G2 /* Runalyzer/CoachingEngine/CoachingEngine.swift */,",
        "Z1X2C3V4B5N6M7L8K9J0H1G2 /* Runalyzer/CoachingEngine/CoachingEngine.swift */,\n\t\t\t\tF1R2A3M4B5O6I7S8E9E0N1G3 /* FramboiseEngine.swift */,"
    )

    # Add to PBXSourcesBuildPhase
    content = content.replace(
        "M1N2B3V4C5X6Z7A8S9D0F1G2 /* Runalyzer/CoachingEngine/CoachingEngine.swift in Sources */,",
        "M1N2B3V4C5X6Z7A8S9D0F1G2 /* Runalyzer/CoachingEngine/CoachingEngine.swift in Sources */,\n\t\t\t\tF1R2A3M4B5O6I7S8E9E0N1G2 /* FramboiseEngine.swift in Sources */,"
    )

with open("Runalyzer.xcodeproj/project.pbxproj", "w") as f:
    f.write(content)
