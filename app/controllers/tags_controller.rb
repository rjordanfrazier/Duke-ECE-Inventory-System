class TagsController < ApplicationController

  before_action :check_logged_in_user, :check_manager_or_admin

  def show
  end

  def index
    @tags = Tag.order(:name).paginate(page: params[:page], per_page: 10)
  end

  def new
    @tag = Tag.new
  end

  def edit
    @tag = Tag.find(params[:id])
  end

  def destroy
    Tag.find(params[:id]).destroy
    flash[:success] = "Tag deleted!"
    redirect_to tags_path
  end

  def create
    @tag = Tag.new(tag_params)
    if @tag.save
      flash[:success] = "Tag saved"
      redirect_to tags_path
    else
      @tags = Tag.paginate(page: params[:page], per_page: 10)
      flash[:danger] = "Tag not saved"
      render :index
    end
  end

  def update
    @tag = Tag.find(params[:id])

		respond_to do |format|
			if @tag.update_attributes(tag_params)
				format.html { redirect_to tags_path, notice: "Tag name updated successfully" }
				format.json { head :no_content }
			else
				format.html { redirect_to tags_path, alert: "Failed to update name" }
				format.json { render json: @tag.errors, status: :unprocessable_entity }
			end
		end
  end


  private

  # Never trust parameters from the scary internet, only allow the white list through.
  def tag_params
    # Rails 4+ requires you to whitelist attributes in the controller.
    params.fetch(:tag, {}).permit(:name)
  end
end
