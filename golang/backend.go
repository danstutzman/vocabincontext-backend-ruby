package main

import (
	"bytes"
	"database/sql"
	"fmt"
	_ "github.com/lib/pq"
	//	"html"
	"log"
	"net/http"
	"strings"
)

var _, _ = fmt.Println()

type Line struct {
	line_id          int
	song_source_num  int
	num_line_in_song int
	line_words       []*LineWord
	alignment        *Alignment
}

type LineWord struct {
	line_id        int
	word_id        int
	part_of_speech string
	word_lowercase string
}

type Alignment struct {
	song_source_num  int
	num_line_in_song int
}

type Translation struct {
	part_of_speech_and_spanish_word string
	english_word                    string
}

func selectLines(db *sql.DB) []*Line {
	lines := []*Line{}
	sql := `select line_id, song_source_num
	  from lines
  	where song_source_num in (select song_source_num from alignments)`
	rows, err := db.Query(sql)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var line Line
		err := rows.Scan(
			&line.line_id,
			&line.song_source_num)
		if err != nil {
			log.Fatal(err)
		}
		lines = append(lines, &line)
	}
	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}
	return lines
}

func selectAlignments(sourceNums []int, db *sql.DB) []*Alignment {
	alignments := []*Alignment{}
	sql := fmt.Sprintf(`select song_source_num, num_line_in_song
	  from alignments
  	where song_source_num in (%s)`, intSliceToSqlIn(sourceNums))
	rows, err := db.Query(sql)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var alignment Alignment
		err := rows.Scan(
			&alignment.song_source_num,
			&alignment.num_line_in_song)
		if err != nil {
			log.Fatal(err)
		}
		alignments = append(alignments, &alignment)
	}
	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}
	return alignments
}

func selectTranslations(keys []string, db *sql.DB) []*Translation {
	translations := []*Translation{}
	sql := fmt.Sprintf(`select part_of_speech_and_spanish_word, english_word
	  from translations
  	where part_of_speech_and_spanish_word in (%s)`, stringSliceToSqlIn(keys))
	rows, err := db.Query(sql)
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

func uniqInts(items []int) []int {
	uniqItems := []int{}
	seenItems := map[int]bool{}
	for _, item := range items {
		if !seenItems[item] {
			uniqItems = append(uniqItems, item)
			seenItems[item] = true
		}
	}
	return uniqItems
}

func selectLineWords(lineIds []int, db *sql.DB) []*LineWord {
	lineWords := []*LineWord{}
	sql := fmt.Sprintf(`select line_words.line_id,
					word_id,
					part_of_speech,
					word_lowercase
				from line_words
				where line_id in (%s)`, intSliceToSqlIn(lineIds))
	fmt.Println(sql)
	rows, err := db.Query(sql)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var lineWord LineWord
		err := rows.Scan(
			&lineWord.line_id,
			&lineWord.word_id,
			&lineWord.part_of_speech,
			&lineWord.word_lowercase)
		if err != nil {
			log.Fatal(err)
		}
		lineWords = append(lineWords, &lineWord)
	}
	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}
	return lineWords
}

func main() {
	db, err := sql.Open("postgres", "user=postgres dbname=postgres sslmode=disable")
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/api", func(writer http.ResponseWriter, request *http.Request) {
		lines := selectLines(db)

		lineIds := []int{}
		for _, line := range lines {
			lineIds = append(lineIds, line.line_id)
		}

		lineWords := selectLineWords(lineIds, db)

		lineByLineId := map[int]*Line{}
		for _, lineWord := range lineWords {
			line, ok := lineByLineId[lineWord.line_id]
			if !ok {
				line = &Line{
					line_id:    lineWord.line_id,
					line_words: []*LineWord{},
				}
				lineByLineId[lineWord.line_id] = line
			}
			line.line_words = append(line.line_words, lineWord)
		}

		sourceNums := []int{}
		for _, line := range lines {
			sourceNums = append(sourceNums, line.song_source_num)
		}
		sourceNums = uniqInts(sourceNums)

		alignments := selectAlignments(sourceNums, db)

		type SourceNumAndLineNum struct {
			source_num       int
			num_line_in_song int
		}
		alignmentBySourceNumAndLineNum := map[SourceNumAndLineNum]*Alignment{}
		for _, alignment := range alignments {
			key := SourceNumAndLineNum{alignment.song_source_num, alignment.num_line_in_song}
			alignmentBySourceNumAndLineNum[key] = alignment
		}

		for _, line := range lines {
			key := SourceNumAndLineNum{line.song_source_num, line.num_line_in_song}
			alignment, ok := alignmentBySourceNumAndLineNum[key]
			if ok {
				line.alignment = alignment
			}
		}

		translationKeys := []string{}
		for _, lineWord := range lineWords {
			translationKeys = append(translationKeys,
				lineWord.part_of_speech+"-"+lineWord.word_lowercase)
		}

		fmt.Println(translationKeys)
		translations := selectTranslations(translationKeys, db)
		for _, translation := range translations {
			fmt.Println(translation)
		}

		//fmt.Fprintf(writer, "Hello, %q", html.EscapeString(request.URL.Path))
	})

	log.Println("Listening on :8080...")
	log.Fatal(http.ListenAndServe(":8080", nil))

	type row_type struct {
		word_id int
		word    string
	}
	rows, err := db.Query("select word_id, word from words limit 10")
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var row row_type
		err := rows.Scan(&row.word_id, &row.word)
		if err != nil {
			log.Fatal(err)
		}
		log.Println(row)
	}
	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}
}
