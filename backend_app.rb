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
      line_words = LineWord.joins(:line
        ).where('lines.audio_excerpt_filename is not null')
    else
      word_id = Word.find_by_word(query).word_id
      line_words = LineWord.joins(:line).where(word_id: word_id)
    end
    @lines = Line.where('line_id IN (?)', line_words.map { |lw| lw.line_id }.uniq)
    load_alignment_for_lines @lines
    line_by_line_id = {}
    @lines.each do |line|
      line_by_line_id[line.line_id] = line
      line.line_words = []
    end
    line_words.each do |line_word|
      line_by_line_id[line_word.line_id].line_words.push line_word
    end
    @lines.each do |line|
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

    songs = Song.where('song_id IN (?)', @lines.map { |line| line.song_id }.uniq)
    songs = songs.includes(:video)
    song_by_song_id = {}
    songs.each { |song| song_by_song_id[song.song_id] = song }
    @lines.each { |line| line.song = song_by_song_id[line.song_id] }

    text_to_line = {}
    @lines.each do |line|
      text_to_line[line.line] = line if !text_to_line[line.line]
      if text_to_line[line.line].num_repetitions.nil?
        text_to_line[line.line].num_repetitions = 0
      end
      text_to_line[line.line].num_repetitions += 1
    end
    @lines = text_to_line.values

    @lines = @lines.sort_by do |line|
      [
        line.alignment ? 1 : 2,
        -line.num_repetitions
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
end
