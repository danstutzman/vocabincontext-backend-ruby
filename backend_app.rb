require 'fileutils'
require 'json'
require './models'
require 'open3'
require 'sinatra/activerecord'
require 'sinatra/base'
require 'sinatra/cross_origin'
require 'tilt/haml'

YOUTUBE_DL_ENV_PATH = File.exists?('/usr/local/bin/ffmpeg') ?
  '/usr/local/Cellar/ffmpeg/2.8.3/bin' : '/usr/local/bin:/usr/bin'
YOUTUBE_DL = '/usr/local/bin/youtube-dl'
AVCONV = File.exists?('/usr/local/bin/ffmpeg') ? '/usr/local/bin/ffmpeg' :
  '/usr/local/bin/avconv'
AAC_CODEC = File.exists?('/usr/local/bin/avconv') ? 'libfdk_aac' : 'libvo_aacenc'
AAC_BITRATE = (AAC_CODEC == 'libfdk_aac') ? '6k' : '32k'

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
    puts command.join(' ')
    stdout, stderr, status = Open3.capture3(*command)
    if not File.exists? path1
      raise "Command #{command.join(' ')} raised stderr #{stderr}"
    end
  end
  path1
end

def download_22050_mono_m4a video_id
  path2 = "/tmp/youtube_22050_mono/#{video_id}.m4a"
  if not File.exists? path2
    path1 = "/tmp/youtube_44100_stereo/#{video_id}.m4a"
    FileUtils.mkdir_p '/tmp/youtube_44100_stereo'
    command = [
      { 'PATH' => YOUTUBE_DL_ENV_PATH },
      '/usr/bin/python', YOUTUBE_DL,
      "http://www.youtube.com/watch?v=#{video_id}",
      '--extract-audio', '--audio-format', 'm4a',
      '-o', path1
    ]
    puts command.join(' ')
    stdout, stderr, status = Open3.capture3(*command)
    if not File.exists? path1
      raise "Command #{command.join(' ')} raised stderr #{stderr}"
    end

    FileUtils.mkdir_p '/tmp/youtube_22050_mono'
    command = [
      AVCONV, '-i', path1, '-vn', '-c:a', AAC_CODEC, '-profile:a', 'aac_he',
      '-ac', '1', '-ar', '22050', '-b:a', AAC_BITRATE, '-cutoff', '18k',
      '-y', path2
    ]
    puts command.join(' ')
    stdout, stderr, status = Open3.capture3(*command)
    if not File.exists? path2
      raise "Command #{command.join(' ')} raised stderr #{stderr}"
    end

    File.delete path1
  end
  path2
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
  register Sinatra::CrossOrigin

  configure do
    set :haml, format: :html5, escape_html: true, ugly: true
    enable :cross_origin
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
      alignment = line.alignment || Alignment.new({
        song_source_num: @song.source_num,
        num_line_in_song: line_num,
      })
      if new_data && new_data['begin_millis'] && new_data['end_millis']
        alignment.begin_millis = new_data['begin_millis']
        alignment.end_millis   = new_data['end_millis']
        alignment.save!
      else
        alignment.destroy
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

  get '/excerpt.aac' do
    youtube_video_id = params[:video_id]
    begin_millis  = Integer(params[:begin_millis])
    end_millis    = Integer(params[:end_millis])
    begin_time    = begin_millis / 1000.0
    duration_time = (end_millis / 1000.0) - begin_time
    _22050_mono_m4a_path = download_22050_mono_m4a youtube_video_id

    excerpt_path = "/tmp/youtube_22050_mono/excerpt-#{begin_millis}-#{end_millis}.aac"
    FileUtils.mkdir_p '/tmp/youtube_22050_mono'
    command = [
      AVCONV, '-i', _22050_mono_m4a_path, '-acodec', 'copy',
      '-ss', begin_time.to_s, '-t', duration_time.to_s,
      '-y', excerpt_path
    ]
    puts command.join(' ')
    stdout, stderr, status = Open3.capture3(*command)

    data = File.read excerpt_path
    File.delete excerpt_path
    content_type 'audio/aac'
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
    time_multiplier = params['time_multiplier']
    path1 = download_wav video_id
    path3 = "/tmp/youtube/#{video_id}.x#{time_multiplier}.wav"
    if not File.exists? path3
      `/usr/local/bin/sox #{path1} #{path3} tempo #{time_multiplier}`
    end
    send_file path3
  end

  get '/album-cover-path/:sha1' do
    content_type 'image/jpeg'
    File.read("/Users/daniel/dev/search-music-apis/spotify_album_covers/#{params['sha1']}")
  end

  get '/download-aligned-videos' do
    videos = Video.where 'song_source_num in (select song_source_num from alignments)'
    videos.each do |video|
      download_22050_mono_m4a video.youtube_video_id
    end
    'OK'
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

    songs = Song.where('song_id IN (?)', @lines.map { |line| line.song_id }.uniq)
    songs = songs.includes(:video).includes(:api_query)
    song_by_song_id = {}
    songs.each { |song| song_by_song_id[song.song_id] = song }
    @lines.each { |line| line.song = song_by_song_id[line.song_id] }

    @lines = @lines.sort_by do |line|
      [
        line.alignment ? 1 : 2,
        -line.num_repetitions_of_search_word / line.line_words.size.to_f,
      ]
    end

    haml :results
  end

end
