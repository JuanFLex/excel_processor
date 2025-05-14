namespace :commodities do
  desc "Actualizar embeddings para referencias de commodities"
  task update_embeddings: :environment do
    CommodityEmbeddingsUpdaterJob.perform_now
  end
end