create table videos (
  youtube_video_id text not null,
  song_source_num int not null
);
COPY videos FROM STDIN WITH CSV HEADER;
youtube_video_id, song_source_num
WxfXzywKzYs,970984
tOCIsy9tYJs,1065635
cMFVtJJ9NNw,1695356
s8BQUlhPR5w,1778381
K2aByptv2ng,1912629
hlw9YNIPUiE,2056423
hlw9YNIPUiE,2056423
\.
create index idx_videos_youtube_video_id on videos(youtube_video_id);
create index idx_videos_song_source_num on videos(song_source_num);
