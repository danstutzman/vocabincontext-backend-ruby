require 'active_record'

class Line < ActiveRecord::Base
  self.primary_key = 'line_id'
end

class Word < ActiveRecord::Base
  self.primary_key = 'line_id'
end

class WordLine < ActiveRecord::Base
  self.table_name = 'words_lines'
end
