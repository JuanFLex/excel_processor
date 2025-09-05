# frozen_string_literal: true

module SimilarityCalculable
  extend ActiveSupport::Concern
  
  module ClassMethods
    def calculate_cosine_similarity(embedding1, embedding2)
      return 0.0 unless embedding1.is_a?(Array) && embedding2.is_a?(Array)
      return 0.0 unless embedding1.size == embedding2.size
      
      # Calcular producto punto (embeddings ya normalizados)
      embedding1.zip(embedding2).sum { |a, b| a * b }
    end
  end
  
  def calculate_similarity_with(other_embedding)
    return 0.0 unless embedding.is_a?(Array) && other_embedding.is_a?(Array)
    return 0.0 unless embedding.size == other_embedding.size
    
    embedding.zip(other_embedding).sum { |a, b| a * b }
  end
end