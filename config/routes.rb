Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  get 'welcome/index'

  resources :users, except: :new
    get '/signup', to: 'users#new'
    post '/signup', to: 'users#create'
  
  resources :requests

  resources :items


  #Login and Sessions routes
  get   '/login',   to: 'sessions#new'      #Describes the login screen
  post  '/login',   to: 'sessions#create'   #Handles actually logging in
  delete '/logout', to: 'sessions#destroy'  #Handles logging out

  root 'welcome#index'
  
end
