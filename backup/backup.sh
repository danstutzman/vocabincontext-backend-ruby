#!/bin/bash
cd `dirname $0`

pg_dump --clean --no-owner vocabincontext -t videos > videos.sql
pg_dump --clean --no-owner vocabincontext -t alignments > alignments.sql
