class UsersController < ApplicationController
  before_action :set_user, only: [:show, :edit, :update, :destroy]
  # Editing/updating a user credential only can be done when logged in
  before_action :check_logged_in_user, except: [:new, :create]

  # Check_current_user allows users to edit/update currently. Be aware that any method added to check_current_user will be
  # bypassed by admin privileges
  before_action :check_current_user, only: [:show, :edit, :update]
  # Security issue: only admin users can delete users
  before_action :check_admin_user, only: [:create, :destroy , :index]

  def new
    # if logged_in?
    #   redirect_to root_path
    # end
    @user = User.new
  end

  # GET /users
  def index
    @users = User.where(status: 1).paginate(page: params[:page], per_page: 10)
  end

  # GET /users/1
  def show
    @user = User.find(params[:id])
    @requests = @user.requests.paginate(page: params[:page], per_page: 10)
  end

  # GET /users/1/edit
  def edit
    @user = User.find(params[:id])
  end

  # POST /users
  def create
    @user = User.new(user_params)

    # TODO: Status is hardcoded for now until we decide what to do with it
    @user.status = "approved"

    if @user.save
      flash[:success] = "#{@user.username} created"
      redirect_to users_path
    else
      flash.now[:danger] = "Unable to create user! Try again?"
      render action: 'new'
    end
  
	@cart = Request.new(:status => "cart", :user_id => @user.id, :reason => "TBD")
	@cart.save!

	end

  # PATCH/PUT /users/1
  def update
    @user = User.find(params[:id])

    if (params[:password].blank? && !current_user?(@user))
      params.delete(:password)
      params.delete(:password_confirmation)
    end

    if @user.update_attributes(user_params)
      flash[:success] = "Credentials updated successfully"
      redirect_to @user
    else
      render 'edit'
    end
  end

  # DELETE /users/1
  def destroy
    User.find(params[:id]).destroy
    flash[:success] = "User account deleted!"
    redirect_to users_url
  end

  def auth_token
    @user = User.find(params[:id])
    if(current_user?(@user))
      @user = User.find(params[:id])
    else
      flash[:danger] = "You are not User with ID #{@user.id}"
      redirect_to current_user
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_user
    @user = User.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def user_params
    # Rails 4+ requires you to whitelist attributes in the controller.
    params.fetch(:user, {}).permit(:username, :email, :password, :password_confirmation, :privilege)
  end

end
