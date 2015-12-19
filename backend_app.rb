require 'haml'
require 'sinatra/base'

class BackendApp < Sinatra::Base
  configure do
    set :haml, format: :html5, escape_html: true, ugly: true
  end

  get '/' do
    haml :enter_query
  end
end
