class TimeFormatter
  def self.format_duration_minutes(seconds)
    return "never loaded" if seconds.nil?
    "#{(seconds / 60).round(1)}min"
  end

  def self.cache_age_from(timestamp)
    return "never loaded" if timestamp.nil?
    age_seconds = Time.current - timestamp
    format_duration_minutes(age_seconds)
  end
end