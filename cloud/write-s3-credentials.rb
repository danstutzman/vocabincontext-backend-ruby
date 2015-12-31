#!/usr/bin/ruby
require 'csv'

CSV.foreach('vocabincontext-media-excerpts-uploader.csv', headers: true) do |row|
  if row['User Name'] == 'vocabincontext-media-excerpts-uploader'
    File.open 'credentials', 'w' do |file|
      file.write "[default]\n"
      file.write "aws_access_key_id = #{row['Access Key Id']}\n"
      file.write "aws_secret_access_key = #{row['Secret Access Key']}\n"
    end
    `echo mkdir -p .aws | gcloud compute ssh speech-snapshot`
    `gcloud compute copy-files credentials speech-snapshot:.aws/credentials`
    File.delete 'credentials'
  end
end
