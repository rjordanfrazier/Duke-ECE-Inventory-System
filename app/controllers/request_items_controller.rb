class RequestItemsController < ApplicationController
	before_action :check_logged_in_user
	before_action :set_new_quantity, only: [:update]

	def new
		@request_item = RequestItem.new

		if !params[:item_id].blank?
			@request_item[:item_id] = params[:item_id]
		end

		if !RequestItem.where(item_id: params[:item_id]).where(request_id: grab_cart(current_user).id).take.nil?
			flash[:warning] = "This item has already been added to your cart! Edit cart to increase quantity."
			redirect_to request_path(grab_cart(current_user).id)
		else
			# look for cart to link request to item
			@request = grab_cart(current_user)
			@request_item[:request_id] = @request.id
		end

	end

	def edit
		@request_item = RequestItem.find(params[:id])
		@loan_tag_list = @request_item.create_serial_tag_list('loan')
		@disburse_tag_list = @request_item.create_serial_tag_list('disburse')
	end

	def create
		@request_item = RequestItem.new(request_item_params)
		@request_item.curr_user = current_user

		begin
			@request_item.save!
			flash[:success] = "Item #{@request_item.item.unique_name} (Loan: #{@request_item.quantity_loan}, Disburse: #{@request_item.quantity_disburse}) added to the cart"
			redirect_to item_path(@request_item.item.id) and return if params[:from_show] == 'true'; redirect_to items_path
		rescue Exception => e
			flash[:danger] = "You may not add this to the cart! Error: #{e}"
			redirect_to item_path(@request_item.item.id) and return if params[:from_show] == 'true'; redirect_to items_path
		end

	end


	def update_backfill
		@request_item = RequestItem.find(params[:id])
		@request_item.curr_user = current_user
		old_status = @request_item.bf_status
		begin
			@request_item.update_attributes!(bf_status: request_item_params[:bf_status])
			UserMailer.backfill_approved_email(@request_item,old_status).deliver_now
			redirect_to request_path(@request_item.request) and return
		rescue Exception => e
			flash[:danger] = e.message
			redirect_to request_path(@request_item.request) and return
		end
	end

	def update
		@request_item = RequestItem.find(params[:id])
		@request_item.curr_user = current_user
		begin
			@request_item.create_request_item_stocks(params[:serial_tags_disburse], params[:serial_tags_loan])
		rescue Exception => e
			flash[:danger] = e.message
			redirect_to request_path(@request_item.request) and return
		end
		respond_to do |format|
			begin
				@request_item.update_attributes!(request_item_params)
				flash[:success] = "Item #{@request_item.item.unique_name} (Loan: #{@request_item.quantity_loan}, Disburse: #{@request_item.quantity_disburse}) updated in the cart"
				if params[:from_show] == 'serial_tag'
					format.html { redirect_to request_path(@request_item.request.id) and return}
				else
					format.html { redirect_to item_path(@request_item.item.id) and return if params[:from_show] == 'true'; redirect_to items_path }
				end
				format.json { head :no_content }
			rescue Exception => e
				flash[:danger] = e.message
				format.html { redirect_to item_path(@request_item.item.id) and return if params[:from_show] == 'true'; redirect_to items_path }
				format.json { render json: @request_item.errors, status: :unprocessable_entity }
			end
		end

	end

	def show
		@request_item = RequestItem.find(params[:id])
	end

	def destroy
		reqit = RequestItem.find(params[:id])
		req = Request.find(reqit.request_id)
		reqit.destroy!
		flash[:success] = "Item removed from request!"
		redirect_to request_path(req)
	end

	def return
		reqit = RequestItem.find(params[:id])

		if reqit.item.has_stocks && params[:serial_tags_loan_return].nil? && (reqit.bf_status == 'loan' or reqit.bf_status == 'bf_denied' or reqit.bf_status == 'bf_failed')
			flash[:danger] = "Must specify tags to return"
			redirect_to request_path(reqit.request_id) and return
		end

		if (params[:quantity_to_return].to_f > reqit.quantity_loan)
			flash[:danger] = "That's more than are loaned out!"
		else
			reqit.curr_user = current_user
			if Item.find(reqit.item_id).has_stocks
				current_user.return_subrequest(reqit, params[:serial_tags_loan_return], request_item_params[:bf_status])
			else
				current_user.return_subrequest(reqit, params[:quantity_to_return].to_f, request_item_params[:bf_status])
			end

			UserMailer.loan_return_email(reqit,params[:quantity_to_return]).deliver_now
			flash[:success] = "Quantity successfully returned!"
		end
		redirect_to request_path(reqit.request_id)
	end

	def specify_return_serial_tags
		@request_item = RequestItem.find(params[:id])
	end

	def disburse_loaned
		reqit = RequestItem.find(params[:id])
		reqit.curr_user = current_user
		if Item.find(reqit.item_id).has_stocks
			if params[:quantity_to_disburse].nil?
				flash[:danger] = "You must specify serial tags to disburse"
				redirect_to request_path(reqit.request_id) and return
			end
			if (params[:quantity_to_disburse].size > reqit.quantity_loan)
				flash[:danger] = "That's more than are loaned out!"
				redirect_to request_path(reqit.request_id) and return
			else
				begin
					reqit.disburse_loaned_subrequest!(params[:quantity_to_disburse])
				rescue Exception => e
					flash[:danger] = "Cannot convert to disbursement. #{e.message}"
					redirect_to request_path(reqit.request_id) and return
				end
			end
		else
			if (params[:quantity_to_disburse].to_f > reqit.quantity_loan)
				flash[:danger] = "That's more than are loaned out!"
				redirect_to request_path(reqit.request_id) and return
			else
				begin
					reqit.disburse_loaned_subrequest!(params[:quantity_to_disburse])
				rescue Exception => e
					flash[:danger] = "Cannot convert to disbursement. #{e.message}"
					redirect_to request_path(reqit.request_id) and return
				end
			end
		end

		UserMailer.loan_convert_email(reqit, params[:quantity_to_disburse]).deliver_now
		flash[:success] = "Quantity successfully disbursed!"
		redirect_to request_path(reqit.request_id)
	end



	private

# Never trust parameters from the scary internet, only allow the white list through.
	def request_item_params
		# Rails 4+ requires you to whitelist attributes in the controller.
		params.fetch(:request_item, {}).permit(:id, :quantity_loan, :quantity_disburse, :quantity_return, :item_id, :request_id, :quantity_to_return, :quantity_to_disburse, :bf_status)
	end

	def set_new_quantity
		@request_item = RequestItem.find(params[:id])
	end

end
