require 'active_record'

class Line < ActiveRecord::Base
  self.primary_key = 'line_id'
end
