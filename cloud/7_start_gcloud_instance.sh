#!/bin/bash -ex
cd `dirname $0`

gsutil cp ../process.rb gs://speech-danstutzman

VIDEO_ID=SqWrliMzrW8

gcloud compute instances create speech1 \
  --image speech-snapshot \
  --machine-type n1-highmem-2 \
  --preemptible \
  --metadata "startup-script=sudo gem install unicode-utils; if [ ! -e /home/daniel/process.rb ]; then /usr/bin/gsutil rsync gs://speech-danstutzman /home/daniel; fi; chown daniel:daniel /home/daniel/process.rb; sudo -u daniel /usr/bin/ruby /home/daniel/process.rb $VIDEO_ID 2>&1 | tee -a /var/log/process.log"
