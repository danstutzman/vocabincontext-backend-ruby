#!/bin/bash -ex
cd `dirname $0`

gcloud compute instances create speech1 \
  --image speech-snapshot --machine-type n1-highmem-2 --preemptible

gcloud compute copy-files ../reserve.rb speech1:reserve.rb
gcloud compute copy-files vocabincontext-media-excerpts-uploader.csv speech1:vocabincontext-media-excerpts-uploader.csv

echo 'ruby reserve.rb' | gcloud compute ssh speech1 
