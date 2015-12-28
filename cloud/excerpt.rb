require 'json'

TEXT         = 0
BEGIN_MILLIS = 1
END_MILLIS   = 2

def do_excerpt video_id, excerpt
  words, begin_millis, end_millis = excerpt
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
  out_path = "#{video_id}-#{begin_millis}-#{end_millis}.m4a"
  `ffmpeg -i #{video_id}.m4a -vn -c copy -ss #{beginning} -t #{duration} -y #{out_path} 2>/dev/null`
  puts words.join(' ')
  puts out_path
  `aws-cli/bin/aws s3 cp --storage-class STANDARD_IA #{out_path} s3://vocabincontext-media-excerpts/#{out_path}`
  `rm #{out_path}`
  puts '------'
end

words = JSON.parse(File.read('result.json'))
current_excerpt = nil
last_begin_millis = nil
skipped_text = []
words.each do |word|
  if word.size == 3
    next if last_begin_millis && word[BEGIN_MILLIS] <= last_begin_millis
    last_begin_millis = word[BEGIN_MILLIS]

    if current_excerpt && word[BEGIN_MILLIS] - current_excerpt[END_MILLIS] <= 2000
      current_excerpt[END_MILLIS] = word[END_MILLIS]
      current_excerpt[TEXT] += skipped_text
      current_excerpt[TEXT].push word[TEXT]
      skipped_text = []
    else
      do_excerpt 'SqWrliMzrW8', current_excerpt if current_excerpt
      current_excerpt = [[word[0]], word[BEGIN_MILLIS], word[END_MILLIS]]
      skipped_text = []
    end
  else
    skipped_text.push word[TEXT]
  end
end
do_excerpt 'SqWrliMzrW8', current_excerpt if current_excerpt
