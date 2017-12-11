#!/bin/bash -ex

cat backup/alignments.sql backup/videos.sql | ssh -i ~/.ssh/vultr root@vocabincontext.danstutzman.com "docker exec -i postgresql psql -U postgres -d vocabincontext"
