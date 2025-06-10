module ApplicationHelper
      def status_badge_classes(status)
    case status
    when 'completed'
      'bg-gradient-to-r from-emerald-100 to-green-100 text-emerald-800 border border-emerald-200'
    when 'failed'
      'bg-gradient-to-r from-red-100 to-rose-100 text-red-800 border border-red-200'
    when 'processing'
      'bg-gradient-to-r from-amber-100 to-yellow-100 text-amber-800 border border-amber-200 animate-pulse'
    when 'queued' 
      'bg-gradient-to-r from-blue-100 to-indigo-100 text-blue-800 border border-blue-200'
    else
      'bg-gradient-to-r from-gray-100 to-slate-100 text-gray-800 border border-gray-200'
    end
  end
  
  def format_file_size(size_in_bytes)
    return '0 B' if size_in_bytes.nil? || size_in_bytes.zero?
    
    units = ['B', 'KB', 'MB', 'GB']
    size = size_in_bytes.to_f
    unit_index = 0
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end
    
    "#{size.round(2)} #{units[unit_index]}"
  end
  
  def processing_time_in_words(start_time, end_time = nil)
    end_time ||= Time.current
    duration = end_time - start_time
    
    if duration < 60
      "#{duration.round}s"
    elsif duration < 3600
      "#{(duration / 60).round}m"
    else
      "#{(duration / 3600).round(1)}h"
    end
  end
end
