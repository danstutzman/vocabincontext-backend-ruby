create table clips (
  clip_id serial,
  rough_begin_syllable int,
  rough_end_syllable int,
  begin_ms int not null,
  end_ms int not null,
  begin_char int not null,
  end_char int not null
);
