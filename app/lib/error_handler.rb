class ErrorHandler
  def self.with_fallback(operation_name, fallback_value = nil)
    yield
  rescue => e
    Rails.logger.error "Error #{operation_name}: #{e.message}"
    fallback_value
  end
end