package main

type Line struct {
	line_id                 int
	song_source_num         int
	num_line_in_song        int
	line_words              []*LineWord
	alignment               *Alignment
	song_id                 int
	song                    *Song
	num_repetitions_of_line int
	line                    string
}

type LineWord struct {
	line_id                int
	word_id                int
	part_of_speech         string
	word_lowercase         string
	translation            *Translation
	word_rating            *WordRating
	begin_char_punctuation int
	begin_char_highlight   int
	end_char_highlight     int
	end_char_punctuation   int
}

type Alignment struct {
	song_source_num  int
	num_line_in_song int
	begin_millis     int
	end_millis       int
}

type Translation struct {
	part_of_speech_and_spanish_word string
	english_word                    string
}

type Song struct {
	song_id                   int
	song_name                 string
	artist_name               string
	video_youtube_video_id    *string
	api_query_cover_image_url *string
}

type Word struct {
	word_id int
	word    string
}

type WordRating struct {
	word   string
	rating int
}
