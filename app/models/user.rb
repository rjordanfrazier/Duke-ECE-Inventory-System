class User < ApplicationRecord
  include Filterable

  PRIVILEGE_OPTIONS = %w(student manager admin)
  STATUS_OPTIONS = %w(deactivated approved)
  DUKE_EMAIL_REGEX = /\A[\w+\-.]+@duke\.edu\z/i

  # Relation with Requests
  has_many :requests, dependent: :destroy

  # Relation with Logs - not necessarily one-to-many
  # has_many :logs

  # Relation with User_Logs
  has_many :user_logs

  enum privilege: {
    student: 0,
    manager: 1,
    admin: 2
  }, _prefix: :privilege

  enum status: {
    deactivated: 0,
    approved: 1
  }, _prefix: :status

  # Filterable params:
  scope :email,     ->    (email)     { where email: email }
  scope :status,    ->    (status)    { where status: status }
  scope :privilege, ->    (privilege) { where privilege: privilege }


  before_validation {
    # Only downcase if the fields are there
    # TODO: Figure out what to do with emails for local accounts. can't have blank as two local accounts cannot be created then.
    self.username = (username.to_s == '') ? username : username.downcase
    self.email = (email.to_s == '') ? "#{username.to_s}@example.com" : email.downcase
  }

  # Creates the confirmation token before a user is created
  before_create {
    confirmation_token
    generate_authentication_token!
  }

  after_create {
    create_new_cart(self.id)
		create_log("created", 0, self.privilege)
	}

	after_update {
		log_on_privilege_change()
		when_deactivated()
	}
	
  validates :username, presence: true, length: { maximum: 50 },
                       uniqueness: { case_sensitive: false }
  validates :email, presence: true, length: { maximum: 255 },
                       uniqueness: { case_sensitive: false }
  validates :password, presence: true, length: { minimum: 6 }, :if => :password
  validates :privilege, :inclusion => { :in => PRIVILEGE_OPTIONS }
  validates :status, :inclusion => { :in => STATUS_OPTIONS }
  validates :auth_token, uniqueness: true

	# scope that gives us current_user
	#scope :curr_user, lambda { |user| 
	#	where("user.id = ?", user.id)
	#}
	attr_accessor :curr_user

  # Returns the hash digest for a given string, used in fixtures for testing
  def User.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST :
                                                  BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end


  #Adds functionality to save a securely hashed password_digest attribute to the database
  #Adds a pair of virtual attributes (password and password_confirmation), including presence validations upon object creation and a validation requiring that they match.
  #Adds an authenticate method that returns the user when the password is correct and false otherwise
  has_secure_password

  # This method confirms a user has confirmed their email. Generates a random string to assign to the token, which identifies
  # which user to confirm
  def confirmation_token
    if self.confirm_token.blank?
      self.confirm_token = SecureRandom.urlsafe_base64.to_s
    end
  end

  def deactivate
    self.status = 'deactivated'
    self.save!
  end

  def generate_authentication_token!
    begin
      self.auth_token = Devise.friendly_token
    end while self.class.exists?(auth_token: auth_token)
  end

  def create_new_cart(id)
    @cart = Request.new(:status => :cart, :user_id => id, :reason => 'TBD', :request_initiator => id)
    @cart.save!
  end

	def when_deactivated()
		if self.status_was == "approved" && self.status == "deactivated"
			create_log("deactivated", self.privilege, self.privilege)

			# change all user's requests to cancelled
			self.requests.each do |req|
				if req.outstanding?
					req.update("status": "cancelled")
				end
			end		 
		end
	end

	def log_on_privilege_change() 
		old_privilege = self.privilege_was
		new_privilege = self.privilege

		if old_privilege != new_privilege
			create_log("privilege_updated", old_privilege, new_privilege)
		end
	end

	def create_log(action, old_priv, new_priv)
		if self.curr_user.nil?
			curr = nil
		else
			curr = self.curr_user.id
		end

		log = Log.new(:user_id => curr, :log_type => "user")
		log.save!
		userlog = UserLog.new(:log_id => log.id, :user_id => self.id, :action => action, :old_privilege => old_priv, :new_privilege => new_priv)
		userlog.save!

  end

  ##
  # TODO
  # USER-1: make_request
  # Allows individuals to request items from the inventory
  # Input: subrequests, reason, requested_for
  #   subrequests: [{
  #     'item_name': 'sample_item'  # Required
  #     'quantity_loan': 325        # Optional
  #     'quantity_disburse': 522    # Optional
  #     'quantity_return': 42       # Optional
  #     'request_type': 'loan'      # Required; must one of: 'loan', 'disbursement', or 'mixed'
  #     'due_date': '06/07/2015'    # Optional
  #   }, ...]
  #   reason: 'Optional reason here'
  #   requested_for: user
  # Return:
  #   On success: newly created request
  #   On failure: null
  # Throws Exceptions:
  #   On request creation failure
  #
  def make_request(subrequests: [], reason: '', requested_for: self)
    raise Exception.new("The user you're making a request for doesn't exist") unless requested_for

    req = nil
    Request.transaction do
      req = Request.new(
          :status => 'outstanding',
          :reason => reason,
          :request_initiator => self.id,
          :user_id => requested_for.id)
      raise Exception.new("Request creation error. The error hash is: #{req.errors.full_messages}") unless req.save

      subrequests.each do |sub_req|
        requested_item = Item.find_by(:unique_name => sub_req['item_name'])
        raise Exception.new("Cannot request non-existent item named: #{sub_req['item_name']}. Subrequest hash is: #{JSON.pretty_generate(sub_req)}.") unless requested_item

        new_req_item = RequestItem.new(:request_id => req.id,
                                       :item_id => requested_item.id,
                                       :quantity_loan => sub_req['quantity_loan'],
                                       :quantity_disburse => sub_req['quantity_disburse'],
                                       :quantity_return => sub_req['quantity_return'],
                                       :request_type => sub_req['request_type'],
                                       :due_date => sub_req['due_date'])
        raise Exception.new("Subrequest creation error. The error hash is #{new_req_item.errors.full_messages}. Subrequest hash is: #{JSON.pretty_generate(sub_req)}.") unless new_req_item.save
      end

      req.update!(:status => 'approved') unless self.privilege_student?
    end

    return req
  end

  ##
  # TODO
  # USER-2: approve_outstanding_request
  # Allows managers/admins to approve outstanding request
  # Input: @request
  # Output:
  #   On success: updated approved request object
  #   On failure: null
  def approve_outstanding_request(request)

  end

  ##
  # TODO
  # USER-3: deny_outstanding_request
  # Allows managers/admins to deny outstanding request
  # Input: @request
  # Output:
  #   On success: updated denied request object
  #   On failure: null
  def deny_outstanding_request(request)

  end

  ##
  # TODO
  # USER-4: borrowed_items

  ## Class Methods
  def self.filter_by_search(search_input)
    where("username ILIKE ?", "%#{search_input}%")
  end

  def self.isDukeEmail?(email_address)
    return email_address.match(DUKE_EMAIL_REGEX)
  end
end
