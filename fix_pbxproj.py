import re

with open('Runalyzer.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# Add FileReference precisely once
# We find the main block where PBXFileReferences are
ref_block_match = re.search(r'/\* Begin PBXFileReference section \*/.*?(?=/\* End PBXFileReference section \*/)', content, re.DOTALL)
if ref_block_match:
    block = ref_block_match.group(0)
    new_block = block + '\n\t\tAABBCCDDEEFF001122334455 /* Runalyzer/Views/AnimatedLoadingView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Runalyzer/Views/AnimatedLoadingView.swift; sourceTree = SOURCE_ROOT; };'
    content = content.replace(block, new_block)

# Add BuildFile precisely once
build_block_match = re.search(r'/\* Begin PBXBuildFile section \*/.*?(?=/\* End PBXBuildFile section \*/)', content, re.DOTALL)
if build_block_match:
    block = build_block_match.group(0)
    new_block = block + '\n\t\t554433221100FFEEDDCCBBAA /* Runalyzer/Views/AnimatedLoadingView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AABBCCDDEEFF001122334455 /* Runalyzer/Views/AnimatedLoadingView.swift */; };'
    content = content.replace(block, new_block)

# Add to the "Runalyzer" group (source files)
content = re.sub(
    r'(Q1W2E3R4T5Y6U7I8O9P0A1S2 /\* Runalyzer/Views/RunDetailView.swift \*/,)',
    r'\1\n\t\t\t\tAABBCCDDEEFF001122334455 /* Runalyzer/Views/AnimatedLoadingView.swift */,',
    content, count=1
)

# Add to PBXSourcesBuildPhase
content = re.sub(
    r'(Z2X3C4V5B6N7M8L9K0J1H2G3 /\* Runalyzer/Views/RunDetailView.swift in Sources \*/,)',
    r'\1\n\t\t\t\t554433221100FFEEDDCCBBAA /* Runalyzer/Views/AnimatedLoadingView.swift in Sources */,',
    content, count=1
)

with open('Runalyzer.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)
