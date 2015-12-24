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
end
