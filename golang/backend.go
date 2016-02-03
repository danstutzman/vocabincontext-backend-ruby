package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	_ "github.com/lib/pq"
	"log"
	"net/http"
	"sort"
	"strings"
)

const LEFT_DOUBLE_QUOTE = "\u201c"
const RIGHT_DOUBLE_QUOTE = "\u201d"

var _, _ = fmt.Println()

type ExcerptWord struct {
	Before  *string `json:",omitempty"`
	Word    *string `json:",omitempty"`
	After   *string `json:",omitempty"`
	Gloss   *string `json:",omitempty"`
	Rating  *int    `json:",omitempty"`
	Between *string `json:",omitempty"`
}

type Excerpt struct {
	Text          string
	BeginMillis   *int    `json:",omitempty"`
	EndMillis     *int    `json:",omitempty"`
	ArtistName    *string `json:",omitempty"`
	SongName      *string `json:",omitempty"`
	VideoId       *string `json:",omitempty"`
	CoverImageUrl *string `json:",omitempty"`
	Words         []ExcerptWord
	LineId        int
}

type ExcerptList struct {
	Lines []Excerpt
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

func uniqStrings(items []string) []string {
	uniqItems := []string{}
	seenItems := map[string]bool{}
	for _, item := range items {
		if !seenItems[item] {
			uniqItems = append(uniqItems, item)
			seenItems[item] = true
		}
	}
	return uniqItems
}

func IfString(condition bool, then string, else_ string) string {
	if condition {
		return then
	} else {
		return else_
	}
}

func main() {
	db, err := sql.Open("postgres", "user=postgres dbname=postgres sslmode=disable")
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/api", func(writer http.ResponseWriter, request *http.Request) {
		excerptList, err := computeExcerptList(db)
		if err != nil {
			log.Fatal(fmt.Errorf("Error from computeExcerptList: %s", err))
		}

		json.NewEncoder(writer).Encode(excerptList)
	})

	log.Println("Listening on :8080...")
	http.ListenAndServe(":8080", nil)
}

func computeExcerptList(db *sql.DB) (*ExcerptList, error) {
	lines, err := selectLines(db)
	if err != nil {
		return nil, fmt.Errorf("Error from selectLines: %s", err)
	}

	lineByLineId := map[int]*Line{}
	for _, line := range lines {
		lineByLineId[line.line_id] = line
	}

	lineIds := []int{}
	for _, line := range lines {
		lineIds = append(lineIds, line.line_id)
	}

	lineWords, err := selectLineWords(lineIds, db)
	if err != nil {
		return nil, fmt.Errorf("Error from selectLineWords: %s", err)
	}

	for _, lineWord := range lineWords {
		line := lineByLineId[lineWord.line_id]
		line.line_words = append(line.line_words, lineWord)
	}

	sourceNums := []int{}
	for _, line := range lines {
		sourceNums = append(sourceNums, line.song_source_num)
	}
	sourceNums = uniqInts(sourceNums)

	alignments, err := selectAlignments(sourceNums, db)
	if err != nil {
		return nil, fmt.Errorf("Error from selectAlignments: %s", err)
	}

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

	translationInputs := []string{}
	for _, lineWord := range lineWords {
		translationInputs = append(translationInputs,
			lineWord.part_of_speech+"-"+lineWord.word_lowercase)
	}

	translations := selectTranslations(translationInputs, db)
	if err != nil {
		return nil, fmt.Errorf("Error from selectTranslations: %s", err)
	}

	translationByInput := map[string]*Translation{}
	for _, translation := range translations {
		translationByInput[translation.part_of_speech_and_spanish_word] = translation
	}
	//fmt.Println(translationByInput)

	for _, line := range lines {
		for _, lineWord := range line.line_words {
			input := lineWord.part_of_speech + "-" + lineWord.word_lowercase
			lineWord.translation = translationByInput[input]
		}
	}

	songIds := []int{}
	for _, line := range lines {
		songIds = append(songIds, line.song_id)
	}
	songIds = uniqInts(songIds)

	songs, err := selectSongs(songIds, db)
	if err != nil {
		return nil, fmt.Errorf("Error from selectSongs: %s", err)
	}

	songBySongId := map[int]*Song{}
	for _, song := range songs {
		songBySongId[song.song_id] = song
	}
	for _, line := range lines {
		line.song = songBySongId[line.song_id]
	}

	wordIds := []int{}
	for _, line := range lines {
		for _, lineWord := range line.line_words {
			wordIds = append(wordIds, lineWord.word_id)
		}
	}
	words, err := selectWords(wordIds, db)
	if err != nil {
		return nil, fmt.Errorf("Error from selectWords: %s", err)
	}

	wordByWordId := map[int]*Word{}
	for _, word := range words {
		wordByWordId[word.word_id] = word
	}

	wordWords := []string{}
	for _, word := range words {
		wordWords = append(wordWords, word.word)
	}
	wordWords = uniqStrings(wordWords)

	wordRatings, err := selectWordRatings(wordWords, db)
	if err != nil {
		return nil, fmt.Errorf("Error from selectWordRatings: %s", err)
	}

	wordRatingByWord := map[string]*WordRating{}
	for _, wordRating := range wordRatings {
		wordRatingByWord[wordRating.word] = wordRating
	}
	for _, line := range lines {
		for _, lineWord := range line.line_words {
			lineWord.word_rating = wordRatingByWord[lineWord.word_lowercase]
		}
	}

	textToLine := map[string]*Line{}
	for _, line := range lines {
		downcaseWords := []string{}
		for _, lineWord := range line.line_words {
			downcaseWords = append(downcaseWords, lineWord.word_lowercase)
		}
		text := strings.Join(downcaseWords, " ")
		if textToLine[text] == nil {
			textToLine[text] = line
		}
		textToLine[text].num_repetitions_of_line += 1
	}
	lines = []*Line{}
	for _, line := range textToLine {
		lines = append(lines, line)
	}

	sort.Sort(ByRelevance(lines))

	filteredLines := []*Line{}
	for _, line := range lines {
		if line.alignment != nil &&
			line.song != nil &&
			line.song.video_youtube_video_id != nil &&
			line.song.api_query_cover_image_url != nil {
			filteredLines = append(filteredLines, line)
		}
	}
	lines = filteredLines

	lines = lines[0:20]

	excerpts := []Excerpt{}
	for _, line := range lines {
		excerptWords := []ExcerptWord{}
		for w, lineWord := range line.line_words {
			excerptWord := ExcerptWord{}

			runes := []rune(line.line)
			beforeWord := IfString(w == 0, LEFT_DOUBLE_QUOTE, "") +
				string(runes[lineWord.begin_char_punctuation:lineWord.begin_char_highlight])
			if beforeWord != "" {
				excerptWord.Before = &beforeWord
			}

			word := string(runes[lineWord.begin_char_highlight:lineWord.end_char_highlight])
			excerptWord.Word = &word

			afterWord :=
				string(runes[lineWord.end_char_highlight:lineWord.end_char_punctuation]) +
					IfString(w == len(line.line_words)-1, RIGHT_DOUBLE_QUOTE, "")
			if afterWord != "" {
				excerptWord.After = &afterWord
			}

			if lineWord.translation != nil {
				excerptWord.Gloss = &lineWord.translation.english_word
			}

			if lineWord.word_rating != nil {
				excerptWord.Rating = &lineWord.word_rating.rating
			}

			excerptWords = append(excerptWords, excerptWord)

			if w < len(line.line_words)-1 {
				nextWord := line.line_words[w+1]
				betweenWords := string(
					runes[lineWord.end_char_punctuation:nextWord.begin_char_punctuation])
				if strings.TrimSpace(betweenWords) != "" {
					excerptWords = append(excerptWords, ExcerptWord{Between: &betweenWords})
				}
			}
		}

		excerpt := Excerpt{}
		excerpt.Text = line.line
		if line.alignment != nil {
			excerpt.BeginMillis = &line.alignment.begin_millis
			excerpt.EndMillis = &line.alignment.end_millis
		}
		if line.song != nil {
			excerpt.ArtistName = &line.song.artist_name
			excerpt.SongName = &line.song.song_name
			excerpt.VideoId = line.song.video_youtube_video_id
			excerpt.CoverImageUrl = line.song.api_query_cover_image_url
		}
		excerpt.Words = excerptWords
		excerpt.LineId = line.line_id
		excerpts = append(excerpts, excerpt)
	}

	return &ExcerptList{Lines: excerpts}, nil
}
