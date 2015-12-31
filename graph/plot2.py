#!/usr/bin/env python
#coding: utf-8

import math
import png
import re

rows = []
for t in range(1200):
  rows.append([255] * 600)
for filename in ['center.wav.out', 'left.wav.out', 'right.wav.out']:
  with open(filename) as f:
    for line in f:
      match = re.match(r'^([ +-]) (.*?)( +\[([0-9]+):([0-9]+)\])?$', line)
      if match:
        symbol       = match.group(1)
        word         = match.group(2)
        begin_millis = match.group(4) and int(match.group(4))
        end_millis   = match.group(5) and int(match.group(5))
        num_word_in_song = int(word.split('-')[0])
        if begin_millis:
          begin_t = int(math.floor(begin_millis / 200))
          end_t   = int(math.ceil(end_millis / 200))
          for t in xrange(begin_t, end_t):
            #if rows[t][num_word_in_song] != 0:
            #  color = 101 if filename == 'right.wav.out' else 0
            rows[t][num_word_in_song] = 0

  with open(filename) as f:
    for line in f:
      match = re.match(r'^INFO: Utterance result \[(.*)\]$', line)
      if match:
        for word_tuple in match.group(1).split('}, {'):
          match2 = re.match('^{?([^,]+), 1.000, \[(-?[0-9]+):(-?[0-9]+)\]}?$',
              word_tuple)
          if not match2:
            raise Exception("Couldn't parse %s" % word)
          word         = match2.group(1)
          begin_millis = int(match2.group(2))
          end_millis   = int(match2.group(3))
          if word != '<sil>' and word != '</s>' and (end_millis - begin_millis < 3000):
            w = int(word.split('-')[0])
            begin_t = int(math.floor(begin_millis / 200))
            end_t   = int(math.ceil(end_millis / 200))
            for t in xrange(begin_t, end_t):
              if rows[t][w] == 255:
                color = 101 if filename == 'center.wav.out' else 100
                rows[t][w] = color

palette = [(255,255,255)] * 256
palette[0] = (0, 0, 0)
palette[100] = (255, 0, 0)
palette[101] = (0, 0, 255)

f = open('png.png', 'wb')
w = png.Writer(len(rows[0]), len(rows), palette=palette, bitdepth=8)
w.write(f, rows)
f.close()
