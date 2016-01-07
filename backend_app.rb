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
    if query == ''
      line_words = LineWord.joins(:line
        ).where('lines.audio_excerpt_filename is not null')
    else
      word_id = Word.find_by_word(query).word_id
      line_words = LineWord.joins(:line).where(word_id: word_id)
      #line_words = line_words.where('lines.audio_excerpt_filename is not null')
    end
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

  get '/manually-align/:video_id' do
    @song = Song.find_by_youtube_video_id(params[:video_id])
    @song.lines = Line.where(song_id: @song.song_id).order(:line_id)
    haml :manually_align
  end

  post '/manually-align/:video_id' do
    data = JSON.parse(request.env['rack.input'].read)
    @song = Song.find_by_youtube_video_id(params[:video_id])
    @song.lines = Line.where(song_id: @song.song_id).order(:line_id)
    @song.lines.each_with_index do |line, line_num|
      if data[line_num]
        line.end_millis   = data[line_num]['endMillis']
        line.save!
      end
    end
    haml :manually_align
  end

  get '/excerpt.wav' do
    begin_millis  = Integer(params[:begin_millis])
    end_millis    = Integer(params[:end_millis])
    begin_time    = begin_millis / 1000.0
    duration_time = (end_millis - begin_millis) / 1000.0
    filename = "excerpt-#{begin_millis}-#{end_millis}.wav"
    puts "/usr/local/bin/sox /Users/daniel/dev/detect-beats/y8rBC6GCUjg.wav #{filename} trim #{begin_time} #{duration_time}"
    `/usr/local/bin/sox /Users/daniel/dev/detect-beats/y8rBC6GCUjg.wav #{filename} trim #{begin_time} #{duration_time}`
    data = File.read filename
    File.delete filename
    content_type 'audio/wav'
    response.write data
  end

  get '/excerpt-:begin_millis-:end_millis.mp3' do
    begin_millis  = Integer(params[:begin_millis])
    end_millis    = Integer(params[:end_millis])
    begin_time    = begin_millis / 1000.0
    duration_time = (end_millis - begin_millis) / 1000.0
    filename = "excerpt-#{begin_millis}-#{end_millis}.wav"
    puts "/usr/local/bin/sox /Users/daniel/dev/detect-beats/y8rBC6GCUjg.wav #{filename} trim #{begin_time} #{duration_time}"
    `/usr/local/bin/sox /Users/daniel/dev/detect-beats/y8rBC6GCUjg.wav #{filename} trim #{begin_time} #{duration_time}`
    filename_mp3 = filename.gsub(/\.wav$/, '.mp3')
    `/usr/local/bin/lame #{filename} #{filename_mp3}`
    data = File.read filename_mp3
    File.delete filename
    File.delete filename_mp3
    content_type 'audio/mp3'
    response.write data
  end

  get '/align-syllables' do
    @syllables = Syllable.all.order(:begin_ms).to_a
    @song = Song.first #find_by_youtube_video_id(params[:video_id])
    @song.lines = Line.where(song_id: @song.song_id).order(:line_id)
    @text = @song.lines.map { |line| line.line }.join("\n")
    @clips = Clip.order('clip_id desc')
    haml :align_syllables2
  end

  post '/align-syllables' do
    clip = Clip.new
    clip.rough_begin_syllable = params['begin_syllable']
    clip.rough_end_syllable   = params['end_syllable']
    clip.begin_ms   = params['begin_ms']
    clip.end_ms     = params['end_ms']
    clip.begin_char = params['begin_char']
    clip.end_char   = params['end_char']
    clip.save!
    redirect '/align-syllables'
  end
end
