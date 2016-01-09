require 'active_record'

class Line < ActiveRecord::Base
  self.primary_key = 'line_id'

  attr :line_html, true
  attr :alignment, true
  attr :song, true
  attr :num_repetitions_of_line, true
  attr :num_repetitions_of_search_word, true
  has_many :line_words, lambda { order 'num_word_in_song' }
end

class Word < ActiveRecord::Base
  self.primary_key = 'word_id'
end

class LineWord < ActiveRecord::Base
  belongs_to :line
  attr :rating, true
  attr :word, true
end

class Song < ActiveRecord::Base
  self.primary_key = 'song_id'

  has_one :video, foreign_key: 'song_source_num', primary_key: 'source_num'
  has_one :api_query, foreign_key: 'song_source_num', primary_key: 'source_num'
  attr :lines, true
end

class Alignment < ActiveRecord::Base
  self.primary_key = 'alignment_id'
end

class Syllable < ActiveRecord::Base
  self.primary_key = 'syllable_id'
end

class Clip < ActiveRecord::Base
  self.primary_key = 'clip_id'
end

class Video < ActiveRecord::Base
  self.primary_key = 'youtube_video_id'
end

class ApiQuery < ActiveRecord::Base
  self.primary_key = 'api_query_id'
end
