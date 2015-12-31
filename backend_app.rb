require 'json'
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
    line_words = LineWord.where(word_id: word_id)
    lines = Line.where('line_id IN (?)', line_words.map { |lw| lw.line_id }.uniq)
    line_by_line_id = {}
    lines.each do |line|
      line_by_line_id[line.line_id] = line
      line.line_words = []
    end
    line_words.each do |line_word|
      line_by_line_id[line_word.line_id].line_words.push line_word
    end
    lines.each do |line|
      line.line_html = line.line
      line.line_words.each do |line_word|
        line.line_html[line_word.begin_index...line_word.begin_index] += '<b>'
        line.line_words.each do |line_word2|
          line_word2.begin_index += 3 if line_word2.begin_index > line_word.begin_index
          line_word2.end_index += 3   if line_word2.end_index   > line_word.begin_index
        end
        line.line_html[line_word.end_index...line_word.end_index] += '</b>'
        line.line_words.each do |line_word2|
          line_word2.begin_index += 4 if line_word2.begin_index > line_word.end_index
          line_word2.end_index += 4   if line_word2.end_index   > line_word.end_index
        end
      end
    end

    @songs = Song.where('song_id IN (?)', lines.map { |line| line.song_id }.uniq)
    @songs.each do |song|
      song.lines = lines.select { |line| line.song_id == song.song_id }
    end

    haml :results
  end

  get '/video-id-to-lines/:video_id.json', provides: :json do
    video_id = params[:video_id]
    song = Song.find_by_youtube_video_id(video_id) or raise Sinatra::NotFound
    lines = Line.where(song_id: song.song_id).order(:line_id)
    lines.to_json
  end

  post '/upload-excerpts' do
    updated_lines = JSON.parse(request.body.read)
    updated_lines.each do |updated_line|
      line = Line.find(updated_line['line_id'])
      line.audio_excerpt_filename = updated_line['audio_excerpt_filename']
      line.save!
    end
    'OK'
  end
end
