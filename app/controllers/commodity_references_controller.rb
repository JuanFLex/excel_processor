class CommodityReferencesController < ApplicationController
  def index
    @commodities = CommodityReference.order(:level2_desc).page(params[:page]).per(20)
  end
  
  def upload
    # Mostrar formulario para subir archivo CSV
  end
  
  def process_upload
    if params[:file].present?
      result = CommodityReferenceLoader.load_from_csv(params[:file].path)
      
      if result[:success]
        redirect_to commodity_references_path, notice: "Se cargaron #{result[:count]} referencias de commodities."
      else
        redirect_to upload_commodity_references_path, alert: "Error al cargar el archivo: #{result[:error]}"
      end
    else
      redirect_to upload_commodity_references_path, alert: 'Debe seleccionar un archivo.'
    end
  end
end