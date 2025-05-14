def index
  @commodities = CommodityReference.order(:level2_desc).page(params[:page])
end