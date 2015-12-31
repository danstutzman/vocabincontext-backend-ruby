require 'active_record'

class Line < ActiveRecord::Base
  self.primary_key = 'line_id'

  attr :line_words, true
  attr :line_html, true
end

class Word < ActiveRecord::Base
  self.primary_key = 'word_id'
end

class LineWord < ActiveRecord::Base
  belongs_to :line
end

class Song < ActiveRecord::Base
  self.primary_key = 'song_id'

  attr :lines, true
end

class Alignment < ActiveRecord::Base
  self.primary_key = 'alignment_id'
end
