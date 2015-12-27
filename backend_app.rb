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

  post '/reserve-alignment', provides: :json do
    machine_num = Integer(params['machine_num'])
    old_alignment_id = params['old_alignment_id']
    old_result_json = params['old_result_json']

    if old_alignment_id != ''
      old_alignment = Alignment.find(old_alignment_id)
      old_alignment.result_json = old_result_json
      old_alignment.save!

      words = JSON.parse(old_result_json)

      last_aligned_pair = nil
      words.each_with_index do |word, i|
        if words[i].size == 3 &&
            i + 1 < words.size && words[i + 1].size == 3 &&
            (words[i][2] - words[i + 1][1]).abs <= 30 # gap between words <= 30ms
          last_aligned_pair = i
        end
      end
      if last_aligned_pair != nil
        new_alignment = Alignment.new
        new_alignment.song_id = old_alignment.song_id
        new_alignment.begin_seconds =
          old_alignment.begin_seconds + (words[last_aligned_pair][1] * 0.001)
        new_alignment.end_seconds = new_alignment.begin_seconds + 5
        new_alignment.begin_num_word_in_song =
          old_alignment.begin_num_word_in_song + last_aligned_pair
        new_alignment.end_num_word_in_song =
          new_alignment.begin_num_word_in_song + 15
        new_alignment.save!
      end
    end

    reservation_expires_after_n_seconds = 60 * 5
    output = ActiveRecord::Base.connection.execute %Q[
      UPDATE alignments
      SET reserved_by_machine_num = #{machine_num}, reserved_at = NOW()
      WHERE alignment_id IN (
        SELECT alignment_id
        FROM alignments
        WHERE (reserved_at IS NULL OR extract(epoch from now() - reserved_at) >
          #{reservation_expires_after_n_seconds})
        AND result_json IS NULL
        ORDER BY alignment_id ASC
        LIMIT 1
        FOR UPDATE
      )
      RETURNING alignment_id;
    ]
    alignments = output.map { |row|
      alignment_id = output[0]['alignment_id']
      alignment = Alignment.find(alignment_id)
      song = Song.find(alignment.song_id)
      line_words = LineWord.where(song_id: alignment.song_id).
        where("num_word_in_song >= ?", alignment.begin_num_word_in_song).
        where("num_word_in_song < ?",  alignment.end_num_word_in_song).
        order(:num_word_in_song)
      words = Word.where('word_id IN (?)', line_words.map { |lw| lw.word_id }.uniq)
      word_by_word_id = {}
      words.each { |word| word_by_word_id[word.word_id] = word }
      text = line_words.map { |lw| word_by_word_id[lw.word_id].word }.join(' ')
      {
        alignment_id:          alignment_id,
        text:                  text,
        begin_seconds:         alignment.begin_seconds,
        end_seconds:           alignment.end_seconds,
        song_youtube_video_id: song.youtube_video_id,
      }
    }
    alignments[0].to_json
  end
end
