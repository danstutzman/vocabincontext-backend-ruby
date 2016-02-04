package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	_ "github.com/lib/pq"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const LEFT_DOUBLE_QUOTE = "\u201c"
const RIGHT_DOUBLE_QUOTE = "\u201d"

var YOUTUBE_VIDEO_ID_REGEX = regexp.MustCompile("^[a-zA-Z0-9_-]{11}$")

var _, _ = fmt.Println()

type ExcerptWord struct {
	Before  *string `json:"before,omitempty"`
	Word    *string `json:"word,omitempty"`
	After   *string `json:"after,omitempty"`
	Gloss   *string `json:"gloss,omitempty"`
	Rating  *int    `json:"rating,omitempty"`
	Between *string `json:"between,omitempty"`
}

type Excerpt struct {
	Text          string
	BeginMillis   *int          `json:"begin_millis,omitempty"`
	EndMillis     *int          `json:"end_millis,omitempty"`
	ArtistName    *string       `json:"artist_name,omitempty"`
	SongName      *string       `json:"song_name,omitempty"`
	VideoId       *string       `json:"video_id,omitempty"`
	CoverImageUrl *string       `json:"cover_image_url,omitempty"`
	Words         []ExcerptWord `json:"words"`
	LineId        int           `json:"line_id",omitempty"`
}

type ExcerptList struct {
	Lines []Excerpt `json:"lines"`
}

func logTimeElapsed(name string, start time.Time) {
	elapsed := time.Since(start)
	log.Printf("%s took %d ms", name, elapsed/time.Millisecond)
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
	type CommandLineArgs struct {
		postgresCredentialsPath *string
	}
	args := CommandLineArgs{
		postgresCredentialsPath: flag.String(
			"postgres_credentials_path", "", "JSON file with username and password"),
	}
	flag.Parse()

	if *args.postgresCredentialsPath == "" {
		log.Fatal("Missing -postgres_credentials_path")
	}
	postgresCredentialsFile, err := os.Open(*args.postgresCredentialsPath)
	if err != nil {
		log.Fatal(fmt.Errorf("Couldn't os.Open postgres_credentials: %s", err))
	}
	defer postgresCredentialsFile.Close()

	type PostgresCredentials struct {
		Username     *string
		Password     *string
		DatabaseName *string
		SSLMode      *string
	}
	postgresCredentials := PostgresCredentials{}
	decoder := json.NewDecoder(postgresCredentialsFile)
	if err = decoder.Decode(&postgresCredentials); err != nil {
		log.Fatalf("Error using decoder.Decode to parse JSON at %s: %s",
			args.postgresCredentialsPath, err)
	}

	dataSourceName := ""
	if postgresCredentials.Username != nil {
		dataSourceName += " user=" + *postgresCredentials.Username
	}
	if postgresCredentials.Password != nil {
		dataSourceName += " password=" + *postgresCredentials.Password
	}
	if postgresCredentials.DatabaseName != nil {
		dataSourceName += " dbname=" + *postgresCredentials.DatabaseName
	}
	if postgresCredentials.SSLMode != nil {
		dataSourceName += " sslmode=" + *postgresCredentials.SSLMode
	}

	db, err := sql.Open("postgres", dataSourceName)
	if err != nil {
		log.Fatal(fmt.Errorf("Error from sql.Open: %s", err))
	}

	// Test out the database connection immediately to check the credentials
	ignored := 0
	err = db.QueryRow("SELECT 1").Scan(&ignored)
	if err != nil {
		log.Fatal(fmt.Errorf("Error from db.QueryRow: %s", err))
	}

	// Preload all translations into memory instead of slow IN query
	translations, err := selectAllTranslations(db)
	if err != nil {
		log.Fatal(fmt.Errorf("Error from selectAllTranslations: %s", err))
	}
	translationByInput := map[string]*Translation{}
	for _, translation := range translations {
		translationByInput[translation.part_of_speech_and_spanish_word] = translation
	}

	// Preload word ratings too
	wordRatings, err := selectWordRatings(db)
	if err != nil {
		log.Fatal(fmt.Errorf("Error from selectWordRatings: %s", err))
	}
	wordRatingByWord := map[string]*WordRating{}
	for _, wordRating := range wordRatings {
		wordRatingByWord[wordRating.word] = wordRating
	}

	// Precompute response for empty query
	excerptListForEmptyQuery, err := computeExcerptList(
		"", translationByInput, wordRatingByWord, db)
	if err != nil {
		log.Fatal(fmt.Errorf("Error from computeExcerptList: %s", err))
	}

	setCorsHeaders := func(writer http.ResponseWriter) {
		writer.Header().Set("Access-Control-Allow-Origin", "*")
		writer.Header().Set("Access-Control-Allow-Methods",
			"POST, GET, OPTIONS, PUT, DELETE")
		writer.Header().Set("Access-Control-Allow-Headers",
			"Accept, Content-Type, Content-Length, Accept-Encoding, "+
				"X-CSRF-Token, Authorization")
	}

	http.HandleFunc("/api/excerpt_list.json",
		func(writer http.ResponseWriter, request *http.Request) {
			query := request.FormValue("q")

			var excerptList *ExcerptList
			var err error
			if query == "" {
				excerptList = excerptListForEmptyQuery
			} else {
				excerptList, err = computeExcerptList(
					query, translationByInput, wordRatingByWord, db)
				if err != nil {
					log.Fatal(fmt.Errorf("Error from computeExcerptList: %s", err))
				}
			}

			setCorsHeaders(writer)
			json.NewEncoder(writer).Encode(excerptList)
		})

	http.HandleFunc("/api/excerpt.aac",
		func(writer http.ResponseWriter, request *http.Request) {
			youtubeVideoId := request.FormValue("video_id")
			if !YOUTUBE_VIDEO_ID_REGEX.MatchString(youtubeVideoId) {
				log.Fatal(fmt.Errorf("Non-whitelisted characters in youtubeVideoId '%s': %s",
					request.FormValue("video_id"), err))
			}
			youtubeVideoIdSafe := youtubeVideoId
			beginMillis, err := strconv.Atoi(request.FormValue("begin_millis"))
			if err != nil {
				log.Fatal(fmt.Errorf("Error from strconv.Atoi of begin_millis='%s': %s",
					request.FormValue("begin_millis"), err))
			}
			endMillis, err := strconv.Atoi(request.FormValue("end_millis"))
			if err != nil {
				log.Fatal(fmt.Errorf("Error from strconv.Atoi of end_millis='%s': %s",
					request.FormValue("end_millis"), err))
			}

			excerptPath := fmt.Sprintf("/tmp/youtube_22050_mono/excerpt-%d-%d.aac",
				beginMillis, endMillis)
			_22050MonoM4aPath := fmt.Sprintf("/tmp/youtube_22050_mono/%s.m4a",
				youtubeVideoIdSafe)
			os.MkdirAll("/tmp/youtube_22050_mono", 0700)

			var avconvBin string
			if _, err := os.Stat("/usr/local/bin/ffmpeg"); !os.IsNotExist(err) {
				avconvBin = "/usr/local/bin/ffmpeg"
			} else if _, err := os.Stat("/usr/local/bin/avconv"); !os.IsNotExist(err) {
				avconvBin = "/usr/local/bin/avconv"
			} else {
				log.Fatal(fmt.Errorf("Can't find avconv binary"))
			}

			beginTime := float32(beginMillis) / 1000.0
			durationTime := float32(endMillis)/1000.0 - beginTime
			commandArgs := []string{
				"-i", _22050MonoM4aPath,
				"-acodec", "copy",
				"-ss", fmt.Sprintf("%f", beginTime),
				"-t", fmt.Sprintf("%f", durationTime),
				"-y", excerptPath,
			}
			_, err = exec.Command(avconvBin, commandArgs...).Output()
			if err != nil {
				log.Fatal(fmt.Errorf("Error from executing %s %s: %s",
					avconvBin, strings.Join(commandArgs, " "), err))
			}

			aacBytes, err := ioutil.ReadFile(excerptPath)
			if err != nil {
				log.Fatal(fmt.Errorf("Error from ReadFile of %s: %s", excerptPath, err))
			}
			err = os.Remove(excerptPath)
			if err != nil {
				log.Fatal(fmt.Errorf("Error from os.Remove of %s: %s", excerptPath, err))
			}

			setCorsHeaders(writer)
			writer.Header().Set("Content-Type", "audio/aac")
			writer.Write(aacBytes)
		})

	log.Println("Listening on :8080...")
	http.ListenAndServe(":8080", nil)
}

func computeExcerptList(query string, translationByInput map[string]*Translation,
	wordRatingByWord map[string]*WordRating, db *sql.DB) (*ExcerptList, error) {

	defer logTimeElapsed("  computeExcerptList", time.Now())

	var possibleLineIdsFilter []int
	var err error
	if query != "" {
		possibleLineIdsFilter, err = selectLineIdsForQuery(query, db)
		if err != nil {
			return nil, fmt.Errorf("Error from selectLineIdsForQuery: %s", err)
		}
	}

	lines, err := selectLines(possibleLineIdsFilter, db)
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

	if len(lines) > 20 {
		lines = lines[0:20]
	}

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
