package main

import (
	"bytes"
	"database/sql"
	"fmt"
	"log"
	"strings"
	"time"
)

func selectLineIdsForQuery(queryFilter string, db *sql.DB) ([]int, error) {
	logTimeElapsed("    selectLineIdsForQuery", time.Now())
	lineIds := []int{}
	query := `select line_id
	  from line_words
  	where word_id in (select word_id from words where word = $1)`
	rows, err := db.Query(query, queryFilter)
	if err != nil {
		return nil, fmt.Errorf("Error from db.Query: %s", err)
	}
	defer rows.Close()
	for rows.Next() {
		var lineId int
		err := rows.Scan(&lineId)
		if err != nil {
			return nil, fmt.Errorf("Error from rows.Scan: %s", err)
		}
		lineIds = append(lineIds, lineId)
	}
	err = rows.Err()
	if err != nil {
		return nil, fmt.Errorf("Error from rows.Err: %s", err)
	}
	return lineIds, nil
}

func selectLines(possibleLineIdsFilter []int, db *sql.DB) ([]*Line, error) {
	logTimeElapsed("    selectLines", time.Now())
	lines := []*Line{}
	var query string
	if possibleLineIdsFilter == nil {
		query = `select line_id,
			song_source_num,
			song_id,
			line,
			num_line_in_song
	  from lines
  	where song_source_num in (select song_source_num from alignments)`
	} else {
		query = fmt.Sprintf(`select line_id,
			song_source_num,
			song_id,
			line,
			num_line_in_song
	  from lines
  	where line_id in (%s)`, intSliceToSqlIn(possibleLineIdsFilter))
	}
	rows, err := db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("Error from db.Query: %s", err)
	}
	defer rows.Close()
	for rows.Next() {
		var line Line
		err := rows.Scan(
			&line.line_id,
			&line.song_source_num,
			&line.song_id,
			&line.line,
			&line.num_line_in_song)
		if err != nil {
			return nil, fmt.Errorf("Error from rows.Scan: %s", err)
		}
		lines = append(lines, &line)
	}
	err = rows.Err()
	if err != nil {
		return nil, fmt.Errorf("Error from rows.Err: %s", err)
	}
	return lines, nil
}

func selectAlignments(sourceNums []int, db *sql.DB) ([]*Alignment, error) {
	defer logTimeElapsed("    selectAlignments", time.Now())

	alignments := []*Alignment{}
	query := fmt.Sprintf(`select song_source_num,
      num_line_in_song,
      begin_millis,
			end_millis
	  from alignments
  	where song_source_num in (%s)`, intSliceToSqlIn(sourceNums))
	rows, err := db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("Error from db.Query: %s", err)
	}
	defer rows.Close()
	for rows.Next() {
		var alignment Alignment
		err := rows.Scan(
			&alignment.song_source_num,
			&alignment.num_line_in_song,
			&alignment.begin_millis,
			&alignment.end_millis)
		if err != nil {
			return nil, fmt.Errorf("Error from rows.Scan: %s", err)
		}
		alignments = append(alignments, &alignment)
	}
	err = rows.Err()
	if err != nil {
		return nil, fmt.Errorf("Error from rows.Err: %s", err)
	}
	return alignments, nil
}

func selectAllTranslations(db *sql.DB) []*Translation {
	defer logTimeElapsed("    selectAllTranslations", time.Now())

	translations := []*Translation{}
	query := fmt.Sprintf(`select part_of_speech_and_spanish_word, english_word
	  from translations`)
	rows, err := db.Query(query)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var translation Translation
		err := rows.Scan(
			&translation.part_of_speech_and_spanish_word,
			&translation.english_word)
		if err != nil {
			log.Fatal(err)
		}
		translations = append(translations, &translation)
	}
	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}
	return translations
}

func selectSongs(songIds []int, db *sql.DB) ([]*Song, error) {
	defer logTimeElapsed("    selectSongs", time.Now())

	songs := []*Song{}
	query := fmt.Sprintf(`select songs.song_id,
			songs.song_name,
			songs.artist_name,
			videos.youtube_video_id,
			api_queries.cover_image_url
	  from songs
		left join videos on videos.song_source_num = songs.source_num
		left join api_queries on api_queries.song_source_num = songs.source_num
  	where song_id in (%s)`, intSliceToSqlIn(songIds))
	rows, err := db.Query(query)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var song Song
		err := rows.Scan(
			&song.song_id,
			&song.song_name,
			&song.artist_name,
			&song.video_youtube_video_id,
			&song.api_query_cover_image_url)
		if err != nil {
			log.Fatal(err)
		}
		songs = append(songs, &song)
	}
	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}
	return songs, nil
}

func selectWordRatings(words []string, db *sql.DB) ([]*WordRating, error) {
	defer logTimeElapsed("    selectWordRatings", time.Now())

	wordRatings := []*WordRating{}
	query := fmt.Sprintf(`select word, rating
	  from word_ratings
  	where word in (%s)`, stringSliceToSqlIn(words))
	rows, err := db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("Error from db.Query: %s", err)
	}
	defer rows.Close()
	for rows.Next() {
		var wordRating WordRating
		err := rows.Scan(
			&wordRating.word,
			&wordRating.rating)
		if err != nil {
			return nil, fmt.Errorf("Error from rows.Scan: %s", err)
		}
		wordRatings = append(wordRatings, &wordRating)
	}
	err = rows.Err()
	if err != nil {
		return nil, fmt.Errorf("Error from rows.Err: %s", err)
	}
	return wordRatings, nil
}

func intSliceToSqlIn(ids []int) string {
	if len(ids) == 0 {
		return "0"
	} else {
		var buffer bytes.Buffer
		for i, id := range ids {
			if i > 0 {
				buffer.WriteString(",")
			}
			buffer.WriteString(fmt.Sprintf("%d", id))
		}
		return buffer.String()
	}
}

func stringSliceToSqlIn(keys []string) string {
	if len(keys) == 0 {
		return "null"
	} else {
		var buffer bytes.Buffer
		replacer := strings.NewReplacer("'", "''")
		for i, key := range keys {
			if i > 0 {
				buffer.WriteString(",")
			}
			buffer.WriteString("'")
			buffer.WriteString(replacer.Replace(key))
			buffer.WriteString("'")
		}
		return buffer.String()
	}
}

func selectLineWords(lineIds []int, db *sql.DB) ([]*LineWord, error) {
	defer logTimeElapsed("    selectLineWords", time.Now())

	lineWords := []*LineWord{}
	query := fmt.Sprintf(`select line_words.line_id,
					word_id,
					part_of_speech,
					word_lowercase,
					begin_char_punctuation,
					begin_char_highlight,
					end_char_highlight,
					end_char_punctuation
				from line_words
				where line_id in (%s)
				order by num_word_in_song`, intSliceToSqlIn(lineIds))
	rows, err := db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("Error from db.Query: %s", err)
	}
	defer rows.Close()
	for rows.Next() {
		var lineWord LineWord
		err := rows.Scan(
			&lineWord.line_id,
			&lineWord.word_id,
			&lineWord.part_of_speech,
			&lineWord.word_lowercase,
			&lineWord.begin_char_punctuation,
			&lineWord.begin_char_highlight,
			&lineWord.end_char_highlight,
			&lineWord.end_char_punctuation)
		if err != nil {
			return nil, fmt.Errorf("Error from rows.Scan: %s", err)
		}
		lineWords = append(lineWords, &lineWord)
	}
	err = rows.Err()
	if err != nil {
		return nil, fmt.Errorf("Error from rows.Err: %s", err)
	}
	return lineWords, nil
}

func selectWords(wordIds []int, db *sql.DB) ([]*Word, error) {
	defer logTimeElapsed("    selectWords", time.Now())

	words := []*Word{}
	query := fmt.Sprintf(`select word_id
				from words
				where word_id in (%s)`, intSliceToSqlIn(wordIds))
	rows, err := db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("Error from db.Query: %s", err)
	}
	defer rows.Close()
	for rows.Next() {
		var word Word
		err := rows.Scan(
			&word.word_id)
		if err != nil {
			return nil, fmt.Errorf("Error from rows.Scan: %s", err)
		}
		words = append(words, &word)
	}
	err = rows.Err()
	if err != nil {
		return nil, fmt.Errorf("Error from rows.Err: %s", err)
	}
	return words, nil
}
