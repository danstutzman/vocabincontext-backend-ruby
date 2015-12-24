require './models'
require 'sinatra/activerecord'
require 'sinatra/base'
require 'tilt/haml'

class BackendApp < Sinatra::Base
  register Sinatra::ActiveRecordExtension

  configure do
    set :haml, format: :html5, escape_html: true, ugly: true
  end

  get '/' do
    haml :enter_query
  end

  get '/results' do
    query = params['q']
    word_id = Word.find_by_word(query).word_id
    line_ids = WordLine.where(word_id: word_id).map { |wl| wl.line_id }
    @lines = Line.where('line_id IN (?)', line_ids)
    haml :results
  end
end
