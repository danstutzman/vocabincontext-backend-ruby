#!/bin/bash -ex
cd `dirname $0`

gcloud compute instances create speech1 \
  --image speech-snapshot --machine-type n1-highmem-2 --preemptible

gcloud compute ssh speech1 <<EOF
sudo pip install awscli
git clone https://github.com/aws/aws-cli.git
EOF
gcloud compute copy-files ../reserve.rb speech1:reserve.rb
gcloud compute copy-files vocabincontext-media-excerpts-uploader.csv speech1:vocabincontext-media-excerpts-uploader.csv

ruby write-s3-credentials.rb

echo 'ruby reserve.rb' | gcloud compute ssh speech1 
