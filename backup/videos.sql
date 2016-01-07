create table videos (
  youtube_video_id text not null,
  song_source_num int not null
);
COPY videos FROM STDIN WITH CSV HEADER;
youtube_video_id, song_source_num
WxfXzywKzYs,970984
hlw9YNIPUiE,2056423
hlw9YNIPUiE,2056423
\.
create index idx_videos_youtube_video_id on videos(youtube_video_id);
create index idx_videos_song_source_num on videos(song_source_num);
