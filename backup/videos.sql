create table videos (
  youtube_video_id text not null,
  song_source_num int not null
);
COPY videos FROM STDIN WITH CSV HEADER;
youtube_video_id, song_source_num
5YABP0QTMxQ,94324
44tZddEjp5g,802116
4Dc5XBbcCeE,806412
wBoOu1WVUlY,814094
2up_Hybx_eE,823162
CfaMT7gh4Es,851608
2oiGCxh6SEA,916097
2aw7sBQLXcQ,919851
WxfXzywKzYs,970984
tOCIsy9tYJs,1065635
MwTZRfkIPDY,1107485
9XrH-oMPxnw,1150443
ULLAXfqiUGw,1185979
Na22GkXMiE4,1250805
iE6sZq4hwZ0,1285020
eZC08evVZAM,1406363
AH18FtrGbwo,1409187
cMFVtJJ9NNw,1695356
ECE2jR33VZM,1733800
s8BQUlhPR5w,1778381
z3pAS6eKvsc,1875659
-P3_aml2-gc,1891189
K2aByptv2ng,1912629
Ay4QoiOHbi0,1972087
ex-BKVSQ7sU,1991508
BIGhyK4ZIx8,2029160
jveJPT5A3B8,2054674
hlw9YNIPUiE,2056423
hlw9YNIPUiE,2056423
VEOMmAFW1DM,2090650
\.
create index idx_videos_youtube_video_id on videos(youtube_video_id);
create index idx_videos_song_source_num on videos(song_source_num);
