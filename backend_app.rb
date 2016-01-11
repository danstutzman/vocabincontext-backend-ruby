require 'fileutils'
require 'json'
require './models'
require 'open3'
require 'sinatra/activerecord'
require 'sinatra/base'
require 'tilt/haml'

def download_wav video_id
  FileUtils.mkdir_p '/tmp/youtube'
  path1 = "/tmp/youtube/#{video_id}.wav"
  if not File.exists? path1
    command = [
      {'PATH' => '/usr/local/Cellar/ffmpeg/2.8.3/bin'},
      '/usr/bin/python', '/usr/local/bin/youtube-dl',
      "http://www.youtube.com/watch?v=#{video_id}",
      '--extract-audio', '--audio-format', 'wav',
      '-o', "/tmp/youtube/%(id)s.%(ext)s",
    ]
    stdout, stderr, status = Open3.capture3(*command)
    if not File.exists? path1
      raise "Command #{command.join(' ')} raised stderr #{stderr}"
    end
  end
  path1
end

def load_alignment_for_lines lines
  source_nums = lines.map { |line| line.song_source_num }.uniq
  alignments = Alignment.where('song_source_num in (?)', source_nums)
  alignment_by_source_num_and_line_num = {}
  alignments.each do |alignment|
    alignment_by_source_num_and_line_num[
      [alignment.song_source_num, alignment.num_line_in_song]] = alignment
  end
  lines.each do |line|
    alignment = alignment_by_source_num_and_line_num[
       [line.song_source_num, line.num_line_in_song]]
    line.alignment = alignment if alignment
  end
end

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
      @word_id = nil
      line_words = LineWord.joins(:line
        ).where('lines.audio_excerpt_filename is not null')
    else
      @word_id = Word.find_by_word(query).word_id
      line_words = LineWord.joins(:line).where(word_id: @word_id)
    end
    @lines = Line.where('line_id IN (?)', line_words.map { |lw| lw.line_id }.uniq)
    @lines = @lines.includes(:line_words)
    load_alignment_for_lines @lines
    line_by_line_id = {}
    @lines.each do |line|
      line_by_line_id[line.line_id] = line
    end
    line_words.each do |line_word|
      line_by_line_id[line_word.line_id].num_repetitions_of_search_word ||= 0
      line_by_line_id[line_word.line_id].num_repetitions_of_search_word += 1
    end

    translation_inputs = []
    @lines.each do |line|
      translation_inputs += line.line_words.map { |line_word|
        line_word.part_of_speech + '-' + line_word.word_lowercase
      }
    end
    translations = Translation.where('part_of_speech_and_spanish_word in (?)',
      translation_inputs.uniq)
    translations_by_input = {}
    translations.each do |translation|
      translations_by_input[translation.part_of_speech_and_spanish_word] = translation
    end
    @lines.each do |line|
      line.line_words.each do |line_word|
        line_word.translation = translations_by_input[
          line_word.part_of_speech + '-' + line_word.word_lowercase]
      end
    end

    songs = Song.where('song_id IN (?)', @lines.map { |line| line.song_id }.uniq)
    songs = songs.includes(:video).includes(:api_query)
    song_by_song_id = {}
    songs.each { |song| song_by_song_id[song.song_id] = song }
    @lines.each { |line| line.song = song_by_song_id[line.song_id] }

    word_ids = []
    @lines.each { |line| word_ids += line.line_words.map { |lw| lw.word_id } }
    words = Word.where('word_id in (?)', word_ids)
    word_by_word_id = {}
    words.each { |word| word_by_word_id[word.word_id] = word }

    word_ratings = WordRating.where('word in (?)', words.map { |word| word.word }.uniq)
    word_rating_by_word = {}
    word_ratings.each do |word_rating|
      word_rating_by_word[word_rating.word] = word_rating.rating
    end
    @lines.each do |line|
      line.line_words.each do |line_word|
        line_word.word = word_by_word_id[line_word.word_id]
        line_word.rating = word_rating_by_word[line_word.word.word] || 3
      end
    end

    text_to_line = {}
    @lines.each do |line|
      downcase = line.line_words.map { |lw| lw.word.word }.join(' ')
      text_to_line[downcase] = line if !text_to_line[downcase]
      if text_to_line[downcase].num_repetitions_of_line.nil?
        text_to_line[downcase].num_repetitions_of_line = 0
      end
      text_to_line[downcase].num_repetitions_of_line += 1
    end
    @lines = text_to_line.values

    @lines = @lines.sort_by do |line|
      [
        line.alignment ? 1 : 2,
        -line.num_repetitions_of_line,
        -line.num_repetitions_of_search_word / line.line_words.size.to_f,
      ]
    end

    haml :results
  end

  post '/set-video-id' do
    found_set_video_id = false
    params.each do |key, value|
      if match = key.match(/^([0-9]+).set_video_id$/)
        found_set_video_id = true
        source_num = match[1]
        video_id = params["#{source_num}.video_id"].find { |value| value != '' } || ''
        video = Video.find_by_song_source_num(source_num) ||
          Video.new({song_source_num: source_num})
        if video_id != ''
          video.youtube_video_id = video_id
          video.save!
        else
          video.destroy
        end
      end
    end
    raise "Couldn't find set_video_id param" if !found_set_video_id
    redirect params['redirect_url']
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

  get '/manually-align/:source_num' do
    @song = Song.find_by_source_num(params[:source_num])
    @song.lines = Line.where(song_id: @song.song_id).order(:line_id)
    load_alignment_for_lines @song.lines
    haml :manually_align
  end

  post '/manually-align/:source_num' do
    @song = Song.find_by_source_num(params[:source_num])
    data = JSON.parse(request.env['rack.input'].read)
    @song.lines = Line.where(song_id: @song.song_id).order(:line_id)
    load_alignment_for_lines @song.lines
    @song.lines.each_with_index do |line, line_num|
      new_data = data[line_num]
      if new_data && new_data['begin_millis'] && new_data['end_millis']
        alignment = line.alignment || Alignment.new({
          song_source_num: @song.source_num,
          num_line_in_song: line_num,
        })
        alignment.begin_millis = new_data['begin_millis']
        alignment.end_millis   = new_data['end_millis']
        alignment.save!
      end
    end
    'OK'
  end

  get '/excerpt.wav' do
    youtube_video_id = params[:video_id]
    begin_millis  = Integer(params[:begin_millis])
    end_millis    = Integer(params[:end_millis])
    begin_time    = begin_millis / 1000.0
    begin_fade    = [begin_time - 0.5, 0].max
    duration_time = (end_millis / 1000.0) - begin_fade + 0.5
    full_path = download_wav youtube_video_id
    excerpt_path = "/tmp/youtube/excerpt-#{begin_millis}-#{end_millis}.wav"
    command = ["/usr/local/bin/sox", full_path, excerpt_path,
      'trim', begin_fade.to_s, duration_time.to_s,
      'fade', 't', (begin_time - begin_fade).to_s, '0', '0.5',
    ]
    puts command.join(' ')
    stdout, stderr, status = Open3.capture3(*command)
    raise "Command #{command} had stderr #{stderr}" if !File.exists? excerpt_path
    data = File.read excerpt_path
    File.delete excerpt_path
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

  get '/speed-up/:video_id.m4a' do
    video_id = params['video_id']
    path1 = download_wav video_id
    path3 = "/tmp/youtube/#{video_id}.x2.wav"
    if not File.exists? path3
      `/usr/local/bin/sox #{path1} #{path3} tempo 2`
    end
    send_file path3
  end

  get '/album-cover-path/:sha1' do
    content_type 'image/jpeg'
    File.read("/Users/daniel/dev/search-music-apis/spotify_album_covers/#{params['sha1']}")
  end
end
