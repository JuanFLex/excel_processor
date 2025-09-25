module ApplicationHelper
  # Helper method to determine the sort direction for a given column
  def sort_direction(column)
    # If the current sort column matches the given column, toggle the direction
    # Otherwise, default to ascending
    if params[:sort] == column
      params[:direction] == "desc" ? "asc" : "desc"
    else
      "asc"
    end
  end

  # Helper method to add CSS classes for sort indicators
  def sort_class(column)
    if params[:sort] == column
      "sort-indicator #{params[:direction]}"
    else
      "sort-indicator"
    end
  end
  
  # Accessibility helper for screen readers
  def sr_only(text)
    content_tag :span, text, class: "sr-only"
  end
end