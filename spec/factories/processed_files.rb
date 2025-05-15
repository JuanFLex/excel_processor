FactoryBot.define do
  factory :processed_file do
    original_filename { "test_inventory.xlsx" }
    status { "pending" }
    
    factory :completed_processed_file do
      status { "completed" }
      processed_at { Time.current }
      result_file_path { "#{Rails.root}/storage/test_processed_file.xlsx" }
    end
    
    factory :failed_processed_file do
      status { "failed" }
    end
    
    factory :processing_processed_file do
      status { "processing" }
    end
    
    factory :queued_processed_file do
      status { "queued" }
    end
  end
end