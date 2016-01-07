require 'active_record'

class Line < ActiveRecord::Base
  self.primary_key = 'line_id'

  attr :line_words, true
  attr :line_html, true
  attr :alignment, true
end

class Word < ActiveRecord::Base
  self.primary_key = 'word_id'
end

class LineWord < ActiveRecord::Base
  belongs_to :line
end

class Song < ActiveRecord::Base
  self.primary_key = 'song_id'

  has_one :video, foreign_key: 'song_source_num', primary_key: 'source_num'
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
