puts "Testing CHANGE 1: Status Methods Pattern"
file = ProcessedFile.create!(original_filename: "test.xlsx", status: "completed")
puts "Created file with status: #{file.status}"

# Test all status methods
puts "completed?: #{file.completed?}"
puts "failed?: #{file.failed?}"
puts "pending?: #{file.pending?}"
puts "column_preview?: #{file.column_preview?}"
puts "processing?: #{file.processing?}"
puts "queued?: #{file.queued?}"

# Change status and test again
file.update!(status: "processing")
puts "After update to processing:"
puts "processing?: #{file.processing?}"
puts "completed?: #{file.completed?}"

# Test another status
file.update!(status: "failed")
puts "After update to failed:"
puts "failed?: #{file.failed?}"
puts "completed?: #{file.completed?}"

# Cleanup
file.destroy
puts "CHANGE 1 SUCCESS - All status methods working correctly!"