# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

Tag.create([{ name: 'ECE110'}, { name: 'ECE230'}, { name: 'ECE559'}, { name: 'Resistor'}, { name: 'Transistor'},
           { name: 'Capacitor'}])



#Creating Users:

12.times do |n|
  username = Faker::Name.name
  email = "example-#{n+1}@duke.edu"
  password = "password"
  User.create!(username: username,
               email: email,
               status: "waiting",
               privilege: "admin",
               password: password,
               password_confirmation: password)
end


12.times do |n|
  username = Faker::Name.name
  email = "exampleApproved-#{n+1}@duke.edu"
  password = "password"
 
  usr = User.create!(username: username,
               email: email,
               status: "approved",
               privilege: "admin",
               password: password,
               password_confirmation: password,
               auth_token: Devise.friendly_token)

  req = Request.create!(status: "cart",
                        user_id: usr.id,
                        reason: "tbd",
                        request_type: "disbursement")

  UserCart.create!(user_id: usr.id,
                   cart_id: req.id)
end

admin = User.create!(username: "admin", email: "adminusername@duke.edu", status: "approved",
             privilege: "admin", password: "password", password_confirmation: "password",
                     auth_token: Devise.friendly_token)
r = Request.create!(status: "cart", user_id: admin.id, reason: "tbd", request_type: "disbursement")
UserCart.create!(user_id: admin.id, cart_id: r.id)

nonadmin = User.create!(username: "nonadmin", email: "nonadminusername@duke.edu", status: "approved",
             privilege: "student", password: "password", password_confirmation: "password", auth_token: Devise.friendly_token)
re = Request.create!(status: "cart", user_id: nonadmin.id, reason: "tbd", request_type: "disbursement")
UserCart.create!(user_id: nonadmin.id, cart_id: re.id)

yo = User.create(username:"abcd", email: "f@duke.edu" , status: "approved",
                 privilege: "student", password: "yoyoyo", password_confirmation: "yoyoyo", auth_token: Devise.friendly_token)
req = Request.create!(status: "cart", user_id: yo.id, reason: "tbd", request_type: "disbursement")
UserCart.create!(user_id: yo.id, cart_id: req.id)

items = %w[Resistor Transistor Oscilloscope RED_LED Green_LED Capacitor Screw Washer BOE-Bot Electrical_Tape Arduino_Kit
            QTI_Sensor Server_Motor Piezo_Speaker Seven_Segment_Display IC_Chip]

items.each do |item|
  quantity = Faker::Number.number(3)
  model_number = Faker::Number.hexadecimal(6)
  description = Faker::Lorem.paragraph(2, true, 1)
  location = Faker::Address.city

  Item.create!(
    unique_name: item,
    quantity: quantity,
    model_number: model_number,
    description: description,
    location: location
  )
end

# Creating Requests:
50.times do |n|
 # Obtain random user:
 user = User.offset(rand(User.count)).first
 # Random reason:
 reason = Faker::Lorem.paragraph(2, true, 3)

 Request.create!(
     user_id: user.id,
     reason: reason,
     status: "outstanding",
     request_type: "disbursement",
 )
end

# Creating Logs:
# Disbursements:
50.times do |n|
  item = Item.offset(rand(Item.count)).first
  quantity = Faker::Number.number(3)
  user = User.offset(rand(User.count)).first
  request_type = rand(0...3)

  Log.create!(
      item_id: item.id,
      quantity: quantity,
      user_id: user.id,
      request_type: request_type
  )
end
