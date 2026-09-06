import sys
import re
import uuid

def generate_pbx_id():
    return uuid.uuid4().hex[:24].upper()

def add_file_to_pbxproj(pbxproj_path, file_path, group_name="Views"):
    with open(pbxproj_path, 'r') as f:
        content = f.read()

    file_name = file_path.split('/')[-1]

    if file_name in content:
        print(f"{file_name} already exists in project.")
        return

    file_ref_id = generate_pbx_id()
    build_file_id = generate_pbx_id()

    # 1. Add to PBXFileReference
    file_ref_str = f'\t\t{file_ref_id} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_path}; sourceTree = SOURCE_ROOT; }};\n'
    content = re.sub(r'(/\* End PBXFileReference section \*/)', f'{file_ref_str}\\1', content)

    # 2. Add to PBXBuildFile
    build_file_str = f'\t\t{build_file_id} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {file_name} */; }};\n'
    content = re.sub(r'(/\* End PBXBuildFile section \*/)', f'{build_file_str}\\1', content)

    # 3. Add to Sources Build Phase
    source_phase_regex = r'(60924B213CE12D34FBC58D03 /\* Sources \*/ = \{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = \()'
    content = re.sub(source_phase_regex, f'\\1\n\t\t\t\t{build_file_id} /* {file_name} in Sources */,', content)

    with open(pbxproj_path, 'w') as f:
        f.write(content)

    print(f"Added {file_name} to project.")

add_file_to_pbxproj("Runalyzer.xcodeproj/project.pbxproj", "Runalyzer/Views/RunListFilteredView.swift")
