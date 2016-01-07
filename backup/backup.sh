#!/bin/bash
cd `dirname $0`

tee videos.sql <<EOF
create table videos (
  youtube_video_id text not null,
  song_source_num int not null
);
COPY videos FROM STDIN WITH CSV HEADER;
youtube_video_id, song_source_num
EOF

echo "select youtube_video_id, song_source_num from videos order by song_source_num;" | /Applications/Postgres.app/Contents/MacOS/bin/psql -t -A -F"," -U postgres | tee -a videos.sql

tee -a videos.sql <<EOF
\\.
create index idx_videos_youtube_video_id on videos(youtube_video_id);
create index idx_videos_song_source_num on videos(song_source_num);
EOF

tee alignments.sql <<EOF
create table alignments (
  alignment_id serial,
  song_source_num int not null,
  num_line_in_song int not null,
  begin_millis int not null,
  end_millis int not null
);
COPY alignments FROM STDIN WITH CSV HEADER;
song_source_num,num_line_in_song,begin_millis,end_millis
EOF

echo "select song_source_num, num_line_in_song, begin_millis, end_millis from alignments order by song_source_num, num_line_in_song;" | /Applications/Postgres.app/Contents/MacOS/bin/psql -t -A -F"," -U postgres | tee -a alignments.sql

tee -a alignments.sql <<EOF
\\.
create index idx_alignments_song_source_num_num_line_in_song on alignments(song_source_num, num_line_in_song);
EOF
