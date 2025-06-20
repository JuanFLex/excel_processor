class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_admin!

  def index
    @users = User.all
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to admin_users_path, notice: "Usuario creado con éxito"
    else
      render :new
    end
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    if @user.update(user_params)
      redirect_to admin_users_path, notice: "Usuario actualizado"
    else
      render :edit
    end
  end

  def destroy
    @user = User.find(params[:id])
    @user.destroy
    redirect_to admin_users_path, notice: "Usuario eliminado"
  end

  private

  def ensure_admin!
    redirect_to root_path, alert: "Acceso no autorizado" unless current_user.admin?
  end

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation, :admin)
  end
end