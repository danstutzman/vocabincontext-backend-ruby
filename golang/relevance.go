package main

func IfThenInt(condition bool, then int, else_ int) int {
	if condition {
		return then
	} else {
		return else_
	}
}

func IsIntSliceLess(slice1 []int, slice2 []int) bool {
	for i := 0; i < len(slice1); i++ {
		if slice1[i] < slice2[i] {
			return true
		}
		if slice1[i] > slice2[i] {
			return false
		}
	}
	return false
}

type ByRelevance []*Line

func (lines ByRelevance) Len() int {
	return len(lines)
}
func (lines ByRelevance) Swap(i, j int) {
	lines[i], lines[j] = lines[j], lines[i]
}
func (lines ByRelevance) Less(i, j int) bool {
	line1 := lines[i]
	line2 := lines[j]
	line1Fields := []int{
		IfThenInt(line1.alignment != nil, 1, 2),
		-line1.num_repetitions_of_line,
		//		-line1.num_repetitions_of_search_word / float(len(line1.line_words)),
	}
	line2Fields := []int{
		IfThenInt(line2.alignment != nil, 1, 2),
		-line2.num_repetitions_of_line,
		//		-line2.num_repetitions_of_search_word / float(len(line2.line_words)),
	}
	return IsIntSliceLess(line1Fields, line2Fields)
}
