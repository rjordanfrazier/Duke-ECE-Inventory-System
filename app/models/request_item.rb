class RequestItem < ApplicationRecord
  include Filterable

  belongs_to :request
  belongs_to :item
  has_many :attachment
  has_many :request_item_stocks
  has_many :request_item_comments, dependent: :destroy

  ## Constants

  enum bf_status: {
      loan: 0,
      bf_request: 1,
      bf_in_transit: 2,
      bf_denied: 3,
      bf_satisfied: 4,
      bf_failed: 5
  }

  # Scopes for filtering
  scope :request_id, -> (request_id) { where request_id: request_id }
  scope :item_id, -> (item_id) { where item_id: item_id }
  scope :user_id, -> (user_id) { joins(:request).where(requests: { user_id: user_id }) }
  scope :status, -> (status) { joins(:request).where(requests: { status: status }) }
  scope :quantity_loan, -> (quantity_loan) { where quantity_loan: quantity_loan }
  scope :quantity_disburse, -> (quantity_disburse) { where quantity_disburse: quantity_disburse }
  scope :quantity_return, -> (quantity_return) { where quantity_return: quantity_return }
  # scope :serial_tags_loan, -> (serial_tags_loan) { where serial_tags_loan: serial_tags_loan }
  # scope :serial_tags_disburse, -> (serial_tags_disburse) { where serial_tags_disburse: serial_tags_disburse }
  scope :bf_status, -> (bf_status) { where bf_status: bf_status }

  attr_accessor :curr_user
  attr_readonly :request_id, :item_id

  after_update {
    log_on_backfill_change
  }

  before_validation {
    self.quantity_disburse = (self.quantity_disburse.blank?) ?  0 : self.quantity_disburse
    self.quantity_return = (self.quantity_return.blank?) ? 0 : self.quantity_return
    self.quantity_loan = (self.quantity_loan.blank?) ? 0 : self.quantity_loan
  }

  validates :quantity_loan, presence: true, :numericality => {:only_integer => true, :greater_than_or_equal_to => 0}
  validates :quantity_disburse, presence: true, :numericality => {:only_integer => true, :greater_than_or_equal_to => 0}
  validates :quantity_return, presence: true, :numericality => {:only_integer => true, :greater_than_or_equal_to => 0}
  # validates :request_type, :inclusion => { :in => REQUEST_TYPE_OPTIONS }
  #validate :request_type_quantity_validation

  validate  :validates_loan_and_disburse_not_zero

  ##
  # REQ-ITEM-1: oversubscribed?
  # Determines if a subrequest is valid or invalid
  #
  # Input: N/A
  def oversubscribed?
    diff = item[:quantity] - (self[:quantity_disburse] + self[:quantity_loan])

    return (diff < 0)
  end

  ##
  # REQ-ITEM-2: fulfill_subrequest
  # The subaction that happens when a request changes form another status to 'approved', or when a request_item is
  # outright created with corresponding request status 'approved'
  #
  # Input: N/A
  # Output: @item upon success
  def fulfill_subrequest
    @item = self.item
    # item_requested = Item.find(self.item_id)
    if @item.has_stocks
      @item.delete_stocks_through_request_by_list(self)
    else

      disbursement_quantity = (self[:quantity_disburse].nil?) ? 0 : self[:quantity_disburse]
      loan_quantity = (self[:quantity_loan].nil?) ? 0 : self[:quantity_loan]

      # Need to send out minimum stock email if applicable!!

      newItemQuant = @item[:quantity] - disbursement_quantity - loan_quantity
      minimum_stock_email(@item.quantity,newItemQuant, @item)

      @item.update!(:quantity => newItemQuant)
      @item.update!(:quantity_on_loan => item[:quantity_on_loan] + loan_quantity)

    end
  end

  ##
  # REQ-ITEM-3: rollback_fulfill_subrequest
  # The subaction that happens when a request changes from 'approved' to something else or when a request_item is
  # outright deleted with old request status 'approved'
  def rollback_fulfill_subrequest
    disbursement_quantity = (self[:quantity_disburse].nil?) ? 0 : self[:quantity_disburse]
    loan_quantity = (self[:quantity_loan].nil?) ? 0 : self[:quantity_loan]

    @item = self.item
    @item.update!(:quantity => item[:quantity] + disbursement_quantity + loan_quantity)
    @item.update!(:quantity_on_loan => item[:quantity_on_loan] - loan_quantity)
  end


  ##
  # REQ-ITEM-5: disburse_loaned_subrequest
  def disburse_loaned_subrequest!(serial_tags_list)
    @item = self.item
    if @item.has_stocks
      quantity_to_disburse = (serial_tags_list.nil?) ? 0 : serial_tags_list.size
    else
      quantity_to_disburse = (serial_tags_list.nil?) ? 0 : serial_tags_list.to_f
    end

    RequestItem.transaction do
      if @item.has_stocks
				stocks_list = {}
        serial_tags_list.each do |serial_tag|
          # mark req item stock as disbursed, delete stock, change quantity for items and req item quantity
          stock = Stock.find_by(serial_tag: serial_tag)
					stocks_list[stock.id] = serial_tag
          req_item_stock = RequestItemStock.find_by(request_item_id: self.id, stock_id: stock.id)
					
          req_item_stock.status = 'disburse'
          req_item_stock.save!
          stock.destroy

          @item.quantity_on_loan -= 1;
          @item.save!

          self.quantity_loan -= 1;
          self.quantity_disburse +=1 ;
          self.save!
        end
				logid = create_log("disbursed_from_loan", quantity_to_disburse)
				create_stock_logs(logid, stocks_list)				
      else
        raise Exception.new("Quantity to convert must be greater than 0") if quantity_to_disburse <= 0
        create_log("disbursed_from_loan", quantity_to_disburse)
        self.update!(:quantity_loan => self[:quantity_loan] - quantity_to_disburse, :quantity_disburse => self[:quantity_disburse] + quantity_to_disburse)
        @item.update!(:quantity_on_loan => item[:quantity_on_loan] - quantity_to_disburse)
      end
    end
  end

  ##
  # REQ-ITEM-6: create log!!!
  def create_log(action, quan_change)
    itemo = self.item
    itemo.update!(:last_action => action)

    if self.curr_user.nil?
      curr = nil
    else
      curr = self.curr_user.id
    end

    old_name = ""
    old_desc = ""
    old_model = ""

    if itemo.unique_name_was != itemo.unique_name
      old_name = itemo.unique_name_was
    end
    if itemo.description_was != itemo.description
      old_desc = itemo.description_was
    end
    if itemo.model_number_was != itemo.model_number
      old_model = itemo.model_number_was
    end

    log = Log.new(:user_id => curr, :log_type => 'item')
    log.save!
    itemlog = ItemLog.new(:log_id => log.id, :item_id => itemo.id, :action => action, :quantity_change => quan_change, :old_name => old_name, :new_name => itemo.unique_name, :old_desc => old_desc, :new_desc => itemo.description, :old_model_num => old_model, :new_model_num => itemo.model_number, :curr_quantity => itemo.quantity, :affected_request => self.request.id, :has_stocks => itemo.has_stocks)
    itemlog.save!
		return itemlog.id
  end

	def create_stock_logs(itemlog_id, stocks)
		stocks.keys.each do |s_id|
			sil = StockItemLog.new(:item_log_id => itemlog_id, :stock_id => s_id, :curr_serial_tag => stocks[s_id])
			sil.save!
		end
	end

  def log_on_backfill_change
    bf_old = bf_status_was
    bf_new = bf_status
		status = ""

    if bf_old == "loan" and bf_new == "bf_request"
      status = "backfill_requested"			
    elsif bf_old == "bf_request" and bf_new == "bf_in_transit"
			status = "backfill_request_approved"
    elsif bf_old == "bf_request" and bf_new == "bf_denied"
			status = "backfill_request_denied"
    elsif bf_old == "bf_in_transit" and bf_new == "bf_failed"
			status = "backfill_request_failed"
    end
	
		if status != ""
			itemlog = create_log(status, self.quantity_loan)
			if self.item.has_stocks?
				sl = self.create_hash_of_stock_on_loan
				create_stock_logs(itemlog, sl)
			end
		end
  end

	def create_hash_of_stock_on_loan
		req_stocks = self.request_item_stocks.filter({status: 'loan'})
		stocks_list = {}
		req_stocks.each do |req_stock|
			stocks_list[req_stock.stock.id] = req_stock.stock.serial_tag
		end
		return stocks_list
	end

  def determine_subrequest_type
    loan_quantity = (self[:quantity_loan].nil?) ? 0 : self[:quantity_loan]
    return_quantity = (self[:quantity_return].nil?) ? 0 : self[:quantity_return]
    disburse_quantity = (self[:quantity_disburse].nil?) ? 0 : self[:quantity_disburse]

    if loan_quantity <= 0 && return_quantity <= 0 && disburse_quantity <= 0
      return 'mixed'
    elsif loan_quantity <= 0 && return_quantity <= 0 && disburse_quantity > 0
      return 'disbursement'
    elsif loan_quantity <= 0 && return_quantity > 0 && disburse_quantity <= 0
      return 'loan'
    elsif loan_quantity <= 0 && return_quantity > 0 && disburse_quantity > 0
      return 'mixed'
    elsif loan_quantity > 0 && return_quantity <= 0 && disburse_quantity <= 0
      return 'loan'
    elsif loan_quantity > 0 && return_quantity <= 0 && disburse_quantity > 0
      return 'mixed'
    elsif loan_quantity > 0 && return_quantity > 0 && disburse_quantity <= 0
      return 'loan'
    elsif loan_quantity > 0 && return_quantity > 0 && disburse_quantity > 0
      return 'mixed'
    else
      return 'mixed'
    end
  end

  def create_request_item_stocks(serial_tags_disburse, serial_tags_loan)

    serial_tags_disburse = [] unless serial_tags_disburse
    serial_tags_loan = [] unless serial_tags_loan

    raise Exception.new("Cannot specify asset for both disbuse and loan") unless serial_tags_are_unique(serial_tags_disburse, serial_tags_loan)

    # binding.pry
    # Destroy all request item stocks associated with request item in order to remove the previous tags
    RequestItemStock.where(request_item_id: self.id).destroy_all

    RequestItem.transaction do
      serial_tags_disburse.each do |st|
        stock = Stock.find_by(serial_tag: st)
        raise Exception.new("Error in finding requested stock. Input serial tag is: #{st}") unless stock
        rq_item_stock_dis = RequestItemStock.new(request_item_id: self.id, stock_id: stock.id, status: 'disburse')
        rq_item_stock_dis.save!
      end

      serial_tags_loan.each do |st|
        stock = Stock.find_by(serial_tag: st)
        raise Exception.new("Error in finding requested stock. Input serial tag is: #{st}") unless stock
        raise Exception.new("Stock requested for loan is not available: #{st}") unless stock.available

        rq_item_stock_loan = RequestItemStock.new(request_item_id: self.id, stock_id: stock.id, status: 'loan')
        rq_item_stock_loan.save!
      end
      # binding.pry
      raise Exception.new("Request Item cannot be saved. Errors are: #{self.errors.full_messages}") unless self.save
    end

  end

  def create_serial_tag_list(status_type)
    tags = Stock.where(id: RequestItemStock.select(:stock_id)
                               .where(request_item_id: self.id, status: status_type))
    list = []
    tags.each do |f|
      list.push(f.serial_tag)
    end
    return list
  end


  ## Validations

  def validates_loan_and_disburse_not_zero
    errors.add(:base, "Loan and Disburse cannot both be 0") if (quantity_disburse == 0 && quantity_loan == 0 && quantity_return == 0)
  end

  def minimum_stock_email(q_before, q_after, item)
    if q_before >= item.minimum_stock && q_after < item.minimum_stock
      10.times do |i|
        puts "The conditinos except for threshold are met for email threshold to send!!!!"
      end
      if item.stock_threshold_tracked
        puts "THE EMAIL WILL DELIVER NOW"
        UserMailer.minimum_stock_quantity_change(q_before, q_after, item).deliver_now
      end
    end
  end
  # Validates that if a request if approved, the admin has set an appropriate amount of serial tags for each quanityt
  def validates_stock_item_serial_tags_are_set!
    item = self.item
    request = self.request

    num_rq_item_stock_dis = RequestItemStock.where(request_item_id: self.id, status: 'disburse').count
    num_rq_item_stock_loan = RequestItemStock.where(request_item_id: self.id, status: 'loan').count

    if item.has_stocks
      if quantity_disburse != num_rq_item_stock_dis || quantity_loan != num_rq_item_stock_loan
        raise Exception.new("Serial tags must be specified for requested item")
      end
    end
  end

  def request_type_quantity_validation
    case self[:request_type]
      when 'disbursement'
        errors.add(:quantity_disburse, "cannot be negative") unless quantity_disburse > -1
      when 'loan'
        errors.add(:quantity_loan, "cannot be negative") unless quantity_loan > -1
        errors.add(:quantity_return, "cannot be negative") unless quantity_return > -1
      else # when 'mixed'
        errors.add(:quantity_disburse, "cannot be negative") unless quantity_disburse > -1
        errors.add(:quantity_loan, "cannot be negative") unless quantity_loan > -1
        errors.add(:quantity_return, "cannot be negative") unless quantity_return > -1
    end
  end

  private

  def serial_tags_are_unique(serial_tags_disburse, serial_tags_loan)
    !((serial_tags_disburse & serial_tags_loan).size > 0)
  end
end
