# To upload: gsutil cp process.rb gs://speech-danstutzman/process.rb
require 'fileutils'
require 'json'
require 'net/http'
require 'open3'

def execute command
  puts command.join(' ')
  out, err, st = Open3.capture3(*command)
  raise "Exit status #{st.exitstatus} from #{command}" if not st.success?
  [out, err]
end

def normalize s
  s.strip.downcase.split(/[^a-zñáéíóúü´]+/i)
end

def do_excerpt video_id, begin_millis, end_millis
  beginning = sprintf('%02d:%02d:%02d.%02d',
    begin_millis / 3600000,
    (begin_millis % 3600000) / 60000,
    (begin_millis % 60000) / 1000,
    begin_millis % 1000)
  duration_millis = end_millis - begin_millis
  duration = sprintf('%02d:%02d:%02d.%02d',
    duration_millis / 3600000,
    (duration_millis % 3600000) / 60000,
    (duration_millis % 60000) / 1000,
    duration_millis % 1000)
  out_filename = "#{video_id}-#{begin_millis}-#{end_millis}.m4a"
  `ffmpeg -i #{video_id}/long.m4a -vn -c copy -ss #{beginning} -t #{duration} -y #{video_id}/#{out_filename} 2>/dev/null`
  puts out_filename
  `aws-cli/bin/aws s3 cp --storage-class STANDARD_IA #{video_id}/#{out_filename} s3://vocabincontext-media-excerpts/#{out_filename}`
  out_filename
end

def group_alignments alignments
  grouped = []
  alignments.each do |new_alignment|
    added = false
    grouped.each do |old_alignment|
      if (old_alignment[0] - new_alignment[0]).abs < 0.1 &&
         (old_alignment[1] - new_alignment[1]).abs < 0.1
        old_alignment[0] = [old_alignment[0], new_alignment[0]].min
        old_alignment[1] = [old_alignment[1], new_alignment[1]].max
        old_alignment[2] += 1
        added = true
        break
      end
    end
    if not added
      grouped.push [new_alignment[0], new_alignment[1], 1]
    end
  end
  grouped
end
def resolve_t0 grouped
  grouped.each do |alignment|
    return alignment[0] if alignment[2] >= 2
  end
  return nil
end
def resolve_t1 grouped
  grouped.each do |alignment|
    return alignment[1] if alignment[2] >= 2
  end
  return nil
end

def process video_id
  FileUtils.mkdir_p video_id

  lines_path = "#{video_id}/lines.json"
  if not File.exists? lines_path
    execute ['curl', '-f',
      "http://digitalocean.vocabincontext.com/video-id-to-lines/#{video_id}.json",
      '-o', lines_path]
  end

  long_wav_path = "#{video_id}/long.wav"
  if not File.exists? long_wav_path
    execute ['youtube-dl', "http://www.youtube.com/watch?v=#{video_id}", '--id']
    execute ['ffmpeg', '-y', '-i', "#{video_id}.mp4", '-vn', '-acodec', 'copy',
      "#{video_id}/long.m4a", '-nostdin']
    File.delete "#{video_id}.mp4"
    execute ['ffmpeg', '-i', "#{video_id}/long.m4a", long_wav_path, '-nostdin']
  end
  
  short_txt_path = "#{video_id}/short.txt"
  lines = JSON.load(File.read(lines_path))
  File.open short_txt_path, 'w' do |file|
    lines.each do |line|
      file.write line['line'] + "\n"
    end
  end

  center_wav_path = "#{video_id}/center.wav"
  if not File.exists? center_wav_path
    execute ['sox', long_wav_path, '-r', '16000', center_wav_path, 'remix', '1,2']
  end

  left_wav_path = "#{video_id}/left.wav"
  if not File.exists? left_wav_path
    execute ['sox', long_wav_path, '-r', '16000', left_wav_path, 'remix', '1']
  end

  right_wav_path = "#{video_id}/right.wav"
  if not File.exists? right_wav_path
    execute ['sox', long_wav_path, '-r', '16000', right_wav_path, 'remix', '2']
  end

  [center_wav_path, left_wav_path, right_wav_path].each do |wav_path|
    if false #&& not File.exists? "#{wav_path}.out"
      out, err = execute ['java', '-cp',
        'sphinx4/sphinx4-samples/build/libs/sphinx4-samples-5prealpha-SNAPSHOT.jar',
        'edu.cmu.sphinx.demo.aligner.AlignerDemo',
        wav_path,
        short_txt_path,
        'voxforge-es-0.2/model_parameters/voxforge_es_sphinx.cd_ptm_3000',
        'voxforge-es-0.2/etc/voxforge_es_sphinx.dic',
        'g2p/fst/model.fst.ser']
      File.open "#{wav_path}.out", 'w' do |file|
        file.write err + out
      end
    end
  end

  words = []
  lines.each do |line|
    words += normalize(line['line'])
  end

  w2alignments = []
  words.size.times { w2alignments.push [] }
  [center_wav_path, left_wav_path, right_wav_path].each do |wav_path|
    out_path = "#{wav_path}.out"
    w = 0
    File.read(out_path).split("\n").each do |line|
      if match = line.match(/^^([ +-]) (.*?)( +\[([0-9]+):([0-9]+)\])?$/)
        if match[1] == '-' || match[1] == ' '
          word = match[2]
          raise "Got word ##{w}=#{word} instead of #{words[w]}" if words[w] != word
          if match[3]
            new_alignment = [match[4].to_i / 1000.0, match[5].to_i / 1000.0]
            w2alignments[w].push new_alignment
          end
          w += 1
        end
      end
    end
  end

  to_upload = []
  w0 = 0
  lines.each do |line|
    w1 = w0 + normalize(line['line']).size - 1
    t0 = resolve_t0(group_alignments(w2alignments[w0]))
    t1 = resolve_t1(group_alignments(w2alignments[w1]))
    if t0 && t1
      audio_excerpt_filename = do_excerpt video_id, (t0 * 1000).to_i, (t1 * 1000).to_i
      puts words[w0..w1].join(' ')
      to_upload.push({
        line_id: line['line_id'],
        audio_excerpt_filename: audio_excerpt_filename,
      })
    end

    w0 = w1 + 1
  end

  uri = URI.parse 'http://digitalocean.vocabincontext.com/upload-excerpts'
  headers = {'Content-Type' => "application/json"}
  http = Net::HTTP.new uri.host, uri.port
  request = Net::HTTP::Post.new uri.request_uri, headers
  request.body = to_upload.to_json
  response = http.request(request)
  if response.code != '200'
    raise "#{response.code} #{response.message} from POST #{uri}"
  end
end

ARGV.each do |video_id|
  process video_id
end
