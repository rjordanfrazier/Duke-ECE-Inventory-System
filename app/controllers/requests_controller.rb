class RequestsController < ApplicationController
  before_action :set_request, only: [:show, :edit, :update, :destroy, :clear]
  before_action :check_logged_in_user
  before_action :check_requests_corresponds_to_current_user, only: [:edit, :update, :destroy, :show]

  # GET /requests
  def index
    filter_params = params.slice(:status)

    if !is_manager_or_admin?
      filter_params[:user_id] = current_user.id
    end

    @requests = Request.where.not(status: "cancelled").where.not(status: "cart").filter(filter_params).order(:updated_at).paginate(page: params[:page], per_page: 10)
  end

  # GET /requests/1
  def show
    @request = Request.find(params[:id])
    if @request.user_id != current_user.id && @request.status == "cart"
      flash[:danger] = "Request #{@request.id} has not been submitted"
      redirect_to requests_path and return
    end
    @user = @request.user
  end

  # GET /requests/1/edit
  def edit
    @request = Request.find(params[:id])
    @user = @request.user
    if @request.status == 'approved' || @request.status == 'denied'
      redirect_to @request and return
    end
  end

  # PATCH/PUT /requests/1
  def update
    @request.curr_user = current_user
    if params[:user]
      @request.user_id = params[:user][:id]
    end
    old_status = @request.status
    begin
      @request.update_attributes!(request_params)
      # UserMailer.request_edited_email(current_user, @request, @request.user).deliver_now
      flash[:success] = "Operation successful!"
      redirect_to request_path(@request)
    rescue Exception => e
      flash[:error] = "Request could not be successfully updated! #{e.message}"
      redirect_back(fallback_location: request_path(@request))
    end

    #Two separate emails, one if user made own request, or if manager made request for him.

    #If request became approved through manager approving request. No subscriber email required.
    if (old_status == 'outstanding' && request_params[:status] == 'approved')
      userMadeRequest = true
      # UserMailer.request_approved_email_all_subscribers(current_user, @request, userMadeRequest).deliver_now
      UserMailer.request_approved_email(current_user, @request, @request.user,userMadeRequest).deliver_now

      #If request became approved through manager making request for him. Subscriber email required.
    elsif (old_status == 'cart' && request_params[:status] == 'approved')
      userMadeRequest = false
      UserMailer.request_approved_email_all_subscribers(current_user, @request, userMadeRequest).deliver_now

      #If request was initiated through user checking out cart. Subscriber email required.
    elsif (old_status == 'cart' && request_params[:status] == 'outstanding')
      UserMailer.request_initiated_email_all_subscribers(@request.user, @request).deliver_now

      #If request was denied by manager. No subscriber email required.
    elsif (old_status =='outstanding' && request_params[:status] == 'denied')
      UserMailer.request_denied_email(current_user, @request, @request.user).deliver_now

    elsif (old_status =='outstanding' && request_params[:status] == 'cancelled')
      UserMailer.request_cancelled_email(current_user, @request, @request.user).deliver_now
    end
  end

  def clear
    @request.items.destroy_all
    # UserMailer.request_destroyed_email(current_user, @request).deliver_now
    redirect_to request_path(@request)
  end

  # DELETE /requests/1
  ## should we deprecate this??
  def destroy
    if (@request.destroy)
      flash[:success] = "Request destroyed!"
    else
      flash[:danger] = "Unable to destroy request!"
    end
    redirect_to requests_url
  end


  private
  # Use callbacks to share common setup or constraints between actions.
  def set_request
    @request = Request.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def request_params
    params.fetch(:request, {}).permit(:user_id,
                                      :reason,
                                      :status,
                                      :response,
                                      request_items_attributes: [:id, :quantity_loan, :quantity_disburse, :request_type, :request_id, :item_id])
  end

  def log_params
    params.fetch(:request, {}).permit(:item_id,
                                      :user_id)
  end

end