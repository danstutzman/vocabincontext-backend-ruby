require 'json'
require 'open3'
require 'rest-client'

machine_num = `curl -s "http://metadata.google.internal/computeMetadata/v1/instance/id" -H "Metadata-Flavor: Google"`

old_alignment_id = nil
old_result = []
while true
  json = RestClient.post 'http://digitalocean.vocabincontext.com/reserve-alignment',
    machine_num: machine_num,
    old_alignment_id: old_alignment_id,
    old_result_json: JSON.generate(old_result)
  break if json == 'null'
  alignment = JSON.parse(json)

  short_txt_path = 'short.txt'
  File.open short_txt_path, 'w' do |file|
    file.write alignment['text']
    file.write "\n"
  end

  video_id = alignment['song_youtube_video_id']
  long_wav_path = "#{video_id}.wav"
  if !File.exists?(long_wav_path)
    command = ['youtube-dl', "http://www.youtube.com/watch?v=#{video_id}", '--id']
    puts command.join(' ')
    out, err, st = Open3.capture3(*command)

    command = ['ffmpeg', '-y', '-i', "#{video_id}.mp4", '-vn', '-acodec', 'copy',
      "#{video_id}.m4a", '-nostdin']
    puts command.join(' ')
    out, err, st = Open3.capture3(*command)

    command = ['ffmpeg', '-i', "#{video_id}.m4a", "#{video_id}.wav", '-nostdin']
    puts command.join(' ')
    out, err, st = Open3.capture3(*command)
  end

  short_wav_path = 'short.wav'
  beginning_millis = (alignment['begin_seconds'] * 1000).to_i
  duration_millis = (alignment['end_seconds'] * 1000).to_i - beginning_millis
  beginning = sprintf('%02d:%02d:%02d.%02d',
    beginning_millis / 3600000,
    (beginning_millis % 3600000) / 60000,
    (beginning_millis % 60000) / 1000,
    beginning_millis % 1000)
  duration = sprintf('%02d:%02d:%02d.%02d',
    duration_millis / 3600000,
    (duration_millis % 3600000) / 60000,
    (duration_millis % 60000) / 1000,
    duration_millis % 1000)
  command = ['sox', long_wav_path, '-r', '16000', '-c', '1', short_wav_path,
    'trim', beginning, duration]
  puts command.join(' ')
  out, err, st = Open3.capture3(*command)

  command = ['java', '-cp',
    'sphinx4/sphinx4-samples/build/libs/sphinx4-samples-5prealpha-SNAPSHOT.jar',
    'edu.cmu.sphinx.demo.aligner.AlignerDemo',
    short_wav_path,
    short_txt_path,
    'voxforge-es-0.2/model_parameters/voxforge_es_sphinx.cd_ptm_3000',
    'voxforge-es-0.2/etc/voxforge_es_sphinx.dic',
    'g2p/fst/model.fst.ser']
  puts command.join(' ')
  out, err, st = Open3.capture3(*command)

  words = []
  out.split("\n").each do |line|
    if !line.start_with?('-')
      match = line.match(/^([ +]) (.*?) +\[([0-9]+):([0-9]+)\]$/) \
        or raise "Can't parse line #{line}"
      words.push({
        type: (match[1] == '+') ? 'added' : 'present',
        word: match[2],
        begin_millis: match[3].to_i, # + beginning_millis,
        end_millis: match[4].to_i, # + beginning_millis,
      })
    end
  end # next alignment

  old_alignment_id = alignment['alignment_id']
  old_result = words
end # repeat while
