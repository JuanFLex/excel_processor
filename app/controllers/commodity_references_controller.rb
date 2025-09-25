class CommodityReferencesController < ApplicationController
  def index
    @commodities = CommodityReference.search(params[:search])
    
    # Apply scope filter if present
    if params[:scope_filter].present?
      @commodities = @commodities.where(infinex_scope_status: params[:scope_filter])
    end
    
    # Apply sorting if present
    if params[:sort].present?
      sort_column = params[:sort]
      sort_direction = params[:direction] || 'asc'
      
      # Validate sort column to prevent SQL injection
      valid_columns = %w[global_comm_code_desc level1_desc level2_desc level3_desc infinex_scope_status]
      if valid_columns.include?(sort_column)
        @commodities = @commodities.order("#{sort_column} #{sort_direction}")
      else
        @commodities = @commodities.order(:infinex_scope_status, :level2_desc)
      end
    else
      @commodities = @commodities.order(:infinex_scope_status, :level2_desc)
    end
    
    # For CSV export, return all records without pagination
    if params[:format] == 'csv'
      send_data @commodities.to_csv, filename: "commodity-references-#{Date.today}.csv"
      return
    end
    
    @commodities = @commodities.page(params[:page]).per(20)
    @search_query = params[:search]
    @scope_filter = params[:scope_filter]
  end
  
  def upload
    # Mostrar formulario para subir archivo CSV
  end
  
  def process_upload
    # CORREGIDO: Usar la estructura correcta de parámetros
    if params[:commodity_upload]&.[](:file).present?
      file = params[:commodity_upload][:file]
      result = CommodityReferenceLoader.load_from_csv(file.path)
      
      if result[:success]
        redirect_to commodity_references_path, notice: "#{result[:count]} commodity references loaded successfully."
      else
        redirect_to upload_commodity_references_path, alert: "Error loading file: #{result[:error]}"

      end
    else
      redirect_to upload_commodity_references_path, alert: 'Please select a file.'
    end
  end
  
  def edit
    @commodity = CommodityReference.find(params[:id])
  end
  
  def update
    @commodity = CommodityReference.find(params[:id])
    
    if @commodity.update(commodity_params)
      redirect_to commodity_references_path(search: params[:search]), notice: 'Commodity reference updated successfully.'
    else
      render :edit
    end
  end
  
  def search
    query = params[:q]
    
    if query.present?
      commodities = CommodityReference.search(query)
                                    .limit(20)
                                    .select(:id, :level3_desc, :level3_desc_expanded, :typical_mpn_by_manufacturer, :infinex_scope_status)
      
      results = commodities.map do |commodity|
        {
          id: commodity.id,
          text: commodity.level3_desc,
          scope: commodity.infinex_scope_status
        }
      end
      
      render json: results
    else
      render json: []
    end
  end
  
  private
  
  def commodity_params
    params.require(:commodity_reference).permit(:keyword, :mfr, :infinex_scope_status, :level3_desc_expanded, :typical_mpn_by_manufacturer)
  end
end