require 'securerandom'

pbxproj_path = './Runalyzer.xcodeproj/project.pbxproj'
content = File.read(pbxproj_path)

if content.include?('DrillRecommendation.swift')
  puts "Already patched"
else
  build_file_uuid = SecureRandom.hex(12).upcase
  file_ref_uuid = SecureRandom.hex(12).upcase

  # Insert PBXBuildFile
  content = content.sub(
    /(\/\* Begin PBXBuildFile section \*\/\n)/,
    "\\1\t\t#{build_file_uuid} /* DrillRecommendation.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{file_ref_uuid} /* DrillRecommendation.swift */; };\n"
  )

  # Insert PBXFileReference
  content = content.sub(
    /(\/\* Begin PBXFileReference section \*\/\n)/,
    "\\1\t\t#{file_ref_uuid} /* DrillRecommendation.swift */ = {isa = PBXFileReference; includeInIndex = 1; lastKnownFileType = sourcecode.swift; name = DrillRecommendation.swift; path = Runalyzer/Models/DrillRecommendation.swift; sourceTree = \"<group>\"; };\n"
  )

  # Find Models group and insert
  content = content.sub(
    /(\/\* CoachingInsight.swift \*\/,\n)/,
    "\\1\t\t\t\t#{file_ref_uuid} /* DrillRecommendation.swift */,\n"
  )

  # Find Sources build phase and insert
  content = content.sub(
    /(\/\* CoachingInsight.swift in Sources \*\/,\n)/,
    "\\1\t\t\t\t#{build_file_uuid} /* DrillRecommendation.swift in Sources */,\n"
  )

  File.write(pbxproj_path, content)
  puts "Patched pbxproj"
end
