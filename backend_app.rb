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
      'python', YOUTUBE_DL,
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
    song_source_num = params['song_source_num']
    video_id        = params['video_id']
    video = Video.find_by_song_source_num(song_source_num) ||
      Video.new({song_source_num: song_source_num})
    if video_id != ''
      video.youtube_video_id = video_id
      video.save!
    else
      video.destroy
    end
    'OK'
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
end
