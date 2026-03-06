require 'rubygems'
require 'xcodeproj'

project_path = 'WorkTracker.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# The target is WorkTracker
target = project.targets.find { |t| t.name == 'WorkTracker' }

# Find the group for Views
group_path = 'WorkTracker/Views'
group = project.main_group.find_subpath('WorkTracker/Views', true)

# Create the file reference
file_path = 'WorkTracker/Views/MiniWidgetView.swift'
file_ref = group.files.find { |f| f.path == 'MiniWidgetView.swift' }

if file_ref
  puts "File already in group."
else
  # The path should be relative to the group
  file_ref = group.new_file('MiniWidgetView.swift')
  puts "Created file reference."
end

# Add to target if not already there
unless target.source_build_phase.files_references.include?(file_ref)
  target.add_file_references([file_ref])
  puts "Added file reference to target: #{target.name}"
else
  puts "File reference already in target."
end

project.save
puts "Project saved."
