# To upload: gsutil cp process.rb gs://speech-danstutzman/process.rb
require 'fileutils'
require 'json'
require 'net/http'
require 'open3'
require 'unicode_utils/downcase'

class Segment
  attr :w0, true
  attr :w1, true
  attr :t0, true
  attr :t1, true
  attr :aligned, true
  attr :l0, true
  attr :l1, true
  def to_s
    "#{@aligned} L#{@l0}-#{@l1} W#{@w0}-#{@w1} T#{@t0}-#{@t1}"
  end
end

def execute command
  puts command.join(' ')
  out, err, st = Open3.capture3(*command)
  raise "Exit status #{st.exitstatus} from #{command}: #{err}" if not st.success?
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

def resolve_t0 alignments
  t0s_with_score = []
  alignments.each do |new_alignment|
    new_t0, _ = new_alignment
    added = false
    t0s_with_score.each do |t0_with_score|
      old_t0, old_score = t0_with_score
      if (new_t0 - old_t0).abs <= 0.1
        t0_with_score[0] = [new_t0, old_t0].min
        t0_with_score[1] += 1
        added = true
      end
    end
    if not added
      t0s_with_score.push [new_alignment[0], 1]
    end
  end
  t0s_with_score.each do |t0_with_score|
    t0, score = t0_with_score
    return t0 if score == 3
  end
  return nil
end

def resolve_t1 alignments
  t1s_with_score = []
  alignments.each do |new_alignment|
    _, new_t1 = new_alignment
    added = false
    t1s_with_score.each do |t1_with_score|
      old_t1, old_score = t1_with_score
      if (new_t1 - old_t1).abs <= 0.1
        t1_with_score[1] = [new_t1, old_t1].max
        t1_with_score[1] += 1
        added = true
      end
    end
    if not added
      t1s_with_score.push [new_alignment[1], 1]
    end
  end
  t1s_with_score.each do |t1_with_score|
    t1, score = t1_with_score
    return t1 if score >= 2
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

  words = []
  lines = JSON.load(File.read(lines_path))
  lines.each do |line|
    words += normalize(line['line'])
  end
  
  short_txt_path = "#{video_id}/short.txt"
  File.open short_txt_path, 'w' do |file|
    words.each_with_index do |word, w|
      file.write "#{w}-#{word} "
    end
  end

  oov_path = "#{video_id}/oov"
  if not File.exists? oov_path
    word2phonemes = {}
    File.open('voxforge-es-0.2/etc/voxforge_es_sphinx.dic').each_line do |line|
      word, phonemes = line.split(/\s+/)[0], line.split(/\s+/)[1..-1]
      word = UnicodeUtils.downcase(word)
      word2phonemes[word] = phonemes
    end
    File.open oov_path, 'w' do |outfile|
      words.each do |word|
        word = UnicodeUtils.downcase(word)
        if not word2phonemes[word]
          outfile.write word + "\n"
        end
      end
    end
  end

  dict_path = "#{video_id}/dict"
  if not File.exists? dict_path
    out, err = execute ['java', '-cp',
      'g2p/decoder/lib/fst.jar:g2p/decoder/dist/decoder.jar',
      'edu.cmu.sphinx.fst.decoder.Phoneticize',
      'g2p/fst/model.fst.ser', oov_path, '1']
    out.split("\n").each do |line|
      word, timing, phonemes = line.split("\t")
      word2phonemes[UnicodeUtils.downcase(word)] = phonemes.split(/\s+/)
    end
    File.open dict_path, 'w' do |outfile|
      words.each_with_index do |word, w|
        word = UnicodeUtils.downcase(word)
        phonemes = word2phonemes[word].join(' ')
        outfile.write "#{w}-#{word} #{phonemes}\n"
      end
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

  #oops_wav_path = "#{video_id}/oops.wav"
  #if not File.exists? oops_wav_path
  #  execute ['sox', long_wav_path, '-r', '16000', oops_wav_path, 'oops']
  #end

  [center_wav_path, left_wav_path, right_wav_path].each do |wav_path|
    if not File.exists? "#{wav_path}.out"
      out, err = execute ['java', '-cp',
        'sphinx4/sphinx4-samples/build/libs/sphinx4-samples-5prealpha-SNAPSHOT.jar',
        'edu.cmu.sphinx.demo.aligner.AlignerDemo',
        wav_path,
        short_txt_path,
        'voxforge-es-0.2/model_parameters/voxforge_es_sphinx.cd_ptm_3000',
        dict_path]
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
    File.read(out_path).split("\n").each do |line|
      if match = line.match(/^^([ +-]) (.*?)( +\[([0-9]+):([0-9]+)\])?$/)
        if match[1] == '-' || match[1] == ' '
          w = Integer(match[2].split('-')[0])
          if match[3]
            new_alignment = [match[4].to_i / 1000.0, match[5].to_i / 1000.0]
            w2alignments[w].push new_alignment
          end
        end
      end
    end
  end

  w2line_num = {}
  w0 = 0
  lines.each_with_index do |line, l|
    line_len = normalize(line['line']).size
    (w0...(w0 + line_len)).each do |w|
      w2line_num[w] = l
    end
    w0 += line_len
  end

  first_segment = Segment.new
  first_segment.w0 = -1
  first_segment.w1 = -1
  first_segment.t0 = -1
  first_segment.t1 = -1
  first_segment.l0 = -1
  first_segment.l1 = -1
  first_segment.aligned = false

  segments = [first_segment]
  w2alignments.each_with_index do |alignment, w|
    t0 = resolve_t0(w2alignments[w])
    t1 = resolve_t1(w2alignments[w])
    new_aligned = (t0 != nil && t1 != nil)
    l = w2line_num[w]
    if (new_aligned && segments.last.aligned && l == segments.last.l1) ||
       (!new_aligned && !segments.last.aligned)
      segments.last.w1 = w
      segments.last.t1 = t1
      segments.last.l1 = l
    else
      if segments.last.t1 == nil
        segments.last.t1 = t0
      end
      new_segment = Segment.new
      new_segment.w0 = w
      new_segment.w1 = w
      new_segment.t0 = t0 || segments.last.t1
      new_segment.t1 = t1
      new_segment.l0 = l
      new_segment.l1 = l
      new_segment.aligned = new_aligned
      segments.push new_segment
    end
  end
  if segments.last.t1 == nil
    segments.last.t1 = 9999
  end
  segments.shift # remove first_segment

  new_segments = []
  while segments.size > 0
    # When there's an aligned + unaligned + aligned segment, merge it if...
    if segments[0].aligned == true && segments.size >= 3 &&
       segments[1].aligned == false && segments[2].aligned == true
      # ...if middle segment is on the same line
      if segments[0].l0 == segments[2].l1
        segments[2].w0 = segments[0].w0
        segments[2].t0 = segments[0].t0
        segments.shift # throw out segments[0]
        segments.shift # throw out segments[1]
      # ...or if middle segment is short and same line as previous segment
      elsif segments[1].t1 - segments[1].t0 < 1000 &&
          segments[1].l1 == segments[0].l0
        segments[0].w1 = segments[1].w1
        segments[0].t1 = segments[1].t1
        new_segments.push segments.shift # keep segments[0]
        segments.shift # throw out segments[1]
      # ...or if middle segment is short and same line as following segment
      elsif segments[1].t1 - segments[1].t0 < 1000 &&
          segments[1].l0 == segments[2].l0
        segments[2].w0 = segments[1].w0
        segments[2].t0 = segments[1].t0
        new_segments.push segments.shift # keep segments[0]
        segments.shift # throw out segments[1]
      else
        new_segments.push segments.shift
      end
    else
      new_segments.push segments.shift
    end
  end
  segments = new_segments

  segments.each do |segment|
    puts segment.to_s + ' ' + words[segment.w0..segment.w1].join(' ')
  end
end

ARGV.each do |video_id|
  process video_id
end
