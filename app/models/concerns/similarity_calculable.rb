# frozen_string_literal: true

module SimilarityCalculable
  extend ActiveSupport::Concern
  
  module ClassMethods
    def calculate_cosine_similarity(embedding1, embedding2)
      start_time = Time.current
      result = begin
        return 0.0 unless embedding1.is_a?(Array) && embedding2.is_a?(Array)
        return 0.0 unless embedding1.size == embedding2.size
        
        # Calcular producto punto (embeddings ya normalizados)
        embedding1.zip(embedding2).sum { |a, b| a * b }
      ensure
        elapsed_ms = ((Time.current - start_time) * 1000).round(2)
        Rails.logger.debug "⏱️ [TIMING] Cosine similarity calculation: #{elapsed_ms}ms" if elapsed_ms > 1
      end
      result
    end
  end
  
  def calculate_similarity_with(other_embedding)
    start_time = Time.current
    result = begin
      return 0.0 unless embedding.is_a?(Array) && other_embedding.is_a?(Array)
      return 0.0 unless embedding.size == other_embedding.size
      
      embedding.zip(other_embedding).sum { |a, b| a * b }
    ensure
      elapsed_ms = ((Time.current - start_time) * 1000).round(2)
      Rails.logger.debug "⏱️ [TIMING] Item similarity calculation: #{elapsed_ms}ms" if elapsed_ms > 1
    end
    result
  end
end