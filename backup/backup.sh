#!/bin/bash
cd `dirname $0`

pg_dump vocabincontext -t videos > videos.sql
pg_dump vocabincontext -t alignments > alignments.sql
