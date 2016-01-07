create table alignments (
  alignment_id serial,
  song_source_num int not null,
  num_line_in_song int not null,
  begin_millis int not null,
  end_millis int not null
);
COPY alignments FROM STDIN WITH CSV HEADER;
song_source_num,num_line_in_song,begin_millis,end_millis
2056423,0,12892,19161
2056423,2,25221,31937
2056423,3,31937,39181
2056423,5,39181,44382
2056423,6,44382,46681
2056423,7,46681,49814
2056423,9,49814,52114
2056423,10,52114,54969
\.
create index idx_alignments_song_source_num_num_line_in_song on alignments(song_source_num, num_line_in_song);
