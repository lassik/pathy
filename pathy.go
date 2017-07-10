package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
)

const PROGNAME = "pathy"
const PROGVERSION = "0.1.0"

var PathVar string

// TODO: Should extensions be case sensitive? E.g. I Python .py/.pyc
// extensions seem to be (at least on Unix), whereas Windows
// extensions are generally not (Microsoft file systems tend to be
// case insensitive).
type KnownPathVar struct {
	Name       string
	Subdirs    bool
	Extensions []string
}

var KnownPathVars []KnownPathVar

func initKnownPathVars() {
	pathExtensions := []string{}
	if runtime.GOOS == "windows" {
		pathExtensions = []string{".bat", ".cmd", ".exe"}
	}
	KnownPathVars = []KnownPathVar{
		KnownPathVar{"CDPATH", true, []string{}},
		KnownPathVar{"GEM_PATH", false, []string{".rb"}},
		KnownPathVar{"PATH", false, pathExtensions},
		KnownPathVar{"PYTHONPATH", true, []string{".py", ".pyc"}},
	}
}

func writeToFd3(thunk func() (string, error)) {
	defer func() {
		if r := recover(); r != nil {
			fmt.Fprintln(os.Stderr, "fd 3 is not open")
			os.Exit(1)
			panic("a")
		}
	}()
	fd3 := os.NewFile(3, "fd 3")
	info, err := fd3.Stat()
	if err != nil {
		log.Fatal(err)
	}
	if info.Mode()&os.ModeType != os.ModeNamedPipe {
		log.Fatal("fd 3 is not a pipe")
	}
	fd3Output, err := thunk()
	if err != nil {
		log.Fatal(err)
	}
	_, err = fmt.Fprintln(fd3, fd3Output)
	if err != nil {
		log.Fatal(err)
	}
}

func confirm(prompt string) bool {
	fullPrompt := prompt + "? [yN] "
	for {
		var s string
		fmt.Print(fullPrompt)
		fmt.Scanln(&s)
		switch strings.ToLower(strings.TrimSpace(s)) {
		case "yes", "y":
			return true
		case "no", "n", "":
			return false
		}
	}
}

func printPathList(pathList []string) {
	for _, dir := range pathList {
		fmt.Println(dir)
	}
}

func sortInPlace(list []string) {
	sort.SliceStable(
		sort.StringSlice(list),
		func(i, j int) bool {
			return strings.ToLower(list[i]) <
				strings.ToLower(list[j])
		})
}

func sortedPathList(pathList []string) []string {
	sorted := make([]string, len(pathList))
	copy(sorted, pathList)
	sortInPlace(sorted)
	return sorted
}

func sortedKeys(stringSet map[string]bool) []string {
	keys := make([]string, len(stringSet))
	i := 0
	for key, _ := range stringSet {
		keys[i] = key
		i++
	}
	sort.Strings(keys)
	return keys
}

type Problem struct {
	Class string
	Desc  string
	Fix   func(d int, dir string) (newDir string, erred, fixed bool)
}

func noFix(d int, dir string) (newDir string, erred, fixed bool) {
	return dir, false, false
}

func fixBlankEntry(d int, dir string) (newDir string, erred, fixed bool) {
	return "", dir == "", dir == ""
}

func fixCwd(d int, dir string) (newDir string, erred, fixed bool) {
	return dir, dir == ".", false
}

func fixCwdNotLast(d int, dir string) (newDir string, erred, fixed bool) {
	//if d != len(pathList)-1 { return dir, true, false }
	return dir, false, false
}

func fixRelative(d int, dir string) (newDir string, erred, fixed bool) {
	if dir == "" || dir == "." || strings.HasPrefix(dir, "/") {
		return dir, false, false
	}
	return dir, true, false
}

var Problems = []Problem{
	Problem{"style",
		"Duplicate entry.",
		noFix},
	Problem{"security",
		"Blank entry (interpreted as current directory).",
		fixBlankEntry},
	Problem{"security",
		"Current directory in path.",
		fixCwd},
	Problem{"security",
		"Current directory is not the last path entry.",
		fixCwdNotLast},
	Problem{"security",
		"Relative directory in path.",
		fixRelative},
}

func cmdDoctor() {
	nTotal := 0
	pathList := getRawPathList()
	seenDirs := map[string]bool{}
	for _, dir := range pathList {
		problems := []string{}
		_, seenThis := seenDirs[dir] // TODO normalize before checking
		if seenThis {
			problems = append(problems, "Duplicate entry in path")
		}
		seenDirs[dir] = true // TODO normalize?
		nTotal += len(problems)
		if len(problems) > 0 {
			fmt.Printf("Entry [%s]\n", dir)
			for _, problem := range problems {
				fmt.Println("*", problem)
			}
		}
	}
	newPathList := []string{}
	for d, dir := range pathList {
		header := false
		for _, problem := range Problems {
			newDir, found, fixed := problem.Fix(d, dir)
			if found {
				nTotal += 1
			}
			if found && !header {
				fmt.Printf("Entry [%s]\n", dir)
				header = true
			}
			class := fmt.Sprintf("[%s]", problem.Class)
			if found && fixed {
				fmt.Println("*", class, problem.Desc, "[fixed]")
			} else if found {
				fmt.Println("*", class, problem.Desc)
			}
			if !fixed {
				newPathList = append(newPathList, dir)
			} else if newDir != "" {
				newPathList = append(newPathList, newDir)
			}
		}
	}
	if nTotal > 1 {
		fmt.Printf("%d problems found\n", nTotal)
	} else if nTotal == 1 {
		fmt.Println("1 problem found")
	} else {
		fmt.Println("No problems found :)")
	}
}

func clean() {
	// this is done after every operation
	//   remove duplicates
	//   normalize path names (remove trailing / and multiple consecutive / and ./)
}

func listStyleProblems() {
	//   non-existent directories
	//   non-executable files in path
	//   subdirectories in path
}

func listSecurityProblems() {
	//   current directory is not the last entry
	//   relative directory
	//   directory writable by world
	//   directory writable by one or more common groups (such as 'users' or 'www')
	//   symlinks to user-/common-group-writable directories or files in path
}

func getRawPathList() []string {
	return strings.Split(os.Getenv(PathVar), string(os.PathListSeparator))
}

func cleanPathEntry(dir string) string {
	dir = filepath.Clean(dir)
	for strings.HasSuffix(dir, string(os.PathSeparator)) {
		dir = dir[:len(dir)-1]
	}
	return dir
}

func cleanPathList(pathList []string) []string {
	newPathList := []string{}
	seen := map[string]bool{}
	for _, path := range pathList {
		newPath := cleanPathEntry(path)
		if !seen[newPath] {
			newPathList = append(newPathList, newPath)
		}
		seen[newPath] = true
	}
	return newPathList
}

func getCleanPathList() []string {
	return cleanPathList(getRawPathList())
}

func quotedPathFromPathList(pathList []string) string {
	// TODO check if any entries envelop one another
	ans := ""
	for _, dir := range pathList {
		if len(ans) > 0 {
			ans = ans + string(os.PathListSeparator)
		}
		ans = ans + dir
	}
	return ans
}

func exportFromPathList(pathList []string) string {
	return "export " + PathVar + "=" + quotedPathFromPathList(pathList)
}

func setCleanPathList(pathList []string) {
	writeToFd3(func() (string, error) {
		return exportFromPathList(cleanPathList(pathList)), nil
	})
}

func cmdActivate() {
	bin, err := os.Executable()
	if err != nil {
		log.Fatal(err)
	}
	bin, err = filepath.Abs(bin)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(`_pathy_bin=` + bin)
	fmt.Println(``)
	fmt.Println(`pathy() {`)
	fmt.Println(`    exec 4>&1`)
	fmt.Println(`    IFS= _pathy_fd3=$($_pathy_bin "$@" 3>&1 >&4) || return`)
	fmt.Println(`    eval "$_pathy_fd3"`)
	fmt.Println(`    unset _pathy_fd3`)
	fmt.Println(`}`)
	fmt.Println(``)
	fmt.Println(`_pathy_complete() {`)
	fmt.Println(`    IFS=$'\n' COMPREPLY=($(compgen -W "$($_pathy_bin complete "$COMP_CWORD" "${COMP_WORDS[@]}")" -- "${COMP_WORDS[COMP_CWORD]}"))`)
	fmt.Println(`}`)
	fmt.Println(`complete -o nospace -F _pathy_complete pathy`)
}

func keyMatches(key, s string) bool {
	return (key == "" ||
		strings.Contains(strings.ToLower(s), strings.ToLower(key)))
}

func howAboutThoseFiles(getList func([]string) []string) {
	key := ""
	for _, file := range getList(getCleanPathList()) {
		if keyMatches(key, file) {
			fmt.Println(file)
		}
	}
}

func cmdLsFiles() {
	// TODO: Currently always shallow. Would a deep/recursive option be useful?
	howAboutThoseFiles(func(pathList []string) []string {
		ans := []string{}
		for _, dir := range pathList {
			filePaths, _ := filepath.Glob(path.Join(dir, "*"))
			for _, filePath := range filePaths {
				ans = append(ans, filePath)
			}
		}
		sortInPlace(ans)
		return ans
	})
}

func cmdLsNames() {
	howAboutThoseFiles(func(pathList []string) []string {
		nameSet := map[string]bool{}
		for _, dir := range pathList {
			filePaths, _ := filepath.Glob(path.Join(dir, "*"))
			for _, filePath := range filePaths {
				nameSet[filePath] = true
			}
		}
		return sortedKeys(nameSet)
	})
}

func cmdShadow() {
	nameDirs := map[string][]string{}
	for _, dir := range getCleanPathList() {
		filePaths, _ := filepath.Glob(path.Join(dir, "*"))
		for _, filePath := range filePaths {
			name := path.Base(filePath)
			nameDirs[name] = append(nameDirs[name], dir)
		}
	}
	for name, dirs := range nameDirs {
		if len(dirs) < 2 {
			delete(nameDirs, name)
		}
	}
	for name, dirs := range nameDirs {
		fmt.Println()
		fmt.Println(name)
		for _, dir := range dirs {
			fmt.Println("*", dir)
		}
	}
}

func cmdWhich() {
	fmt.Println("which")
}

func cmdEdit() {
	editor := flag.Arg(1)
	if editor == "" {
		editor = os.Getenv("EDITOR")
	}
	if editor == "" {
		log.Fatal("Editor not given and" +
			" EDITOR environment variable is not set")
	}
	// TODO
}

func cmdRunFiles() {
	//files = get_ls_files_table()
	//pid = start_program(...)
	//for _, file := range files {
	//	fmt.Println(file)
	//}
	//os.exit(wait_for_program(pid))
}

func cmdExport() {
	fmt.Println(exportFromPathList(getCleanPathList()))
}

func cmdLs() {
	printPathList(getRawPathList())
}

func cmdPutFirst() {
	setCleanPathList(append(flag.Args()[1:], getRawPathList()...))
}

func cmdPutLast() {
	setCleanPathList(append(getRawPathList(), flag.Args()[1:]...))
}

func cmdRm() {
	key := ""
	if flag.NArg() >= 1 {
		key = flag.Arg(1)
	}
	newPathList := make([]string, 0)
	hadAny := false
	for _, dir := range getCleanPathList() {
		if !hadAny {
			hadAny = true
			fmt.Println("Going through the path list in order. Answer 'y' (yes)")
			fmt.Println("to the entries you want to remove. Default answer is no.")
		}
		rm := keyMatches(key, dir) && confirm(fmt.Sprintf("Remove %s", dir))
		if !rm {
			newPathList = append(newPathList, dir)
		}
	}
	if hadAny {
		setCleanPathList(newPathList)
	} else {
		print("Path is empty")
	}
}

func cmdComplete() {
	if flag.NArg() < 2 {
		os.Exit(1)
	}
	cword, err := strconv.Atoi(flag.Arg(1))
	if err != nil || cword < 1 {
		os.Exit(1)
	}
	cword -= 2
	// flag.Arg(cword) now gets the arg you expect.
	fmt.Println(strconv.Itoa(cword), flag.Arg(cword-1), flag.Arg(cword))
	if cword > 1 && flag.Arg(cword-1) == "-V" {
		for _, knownVar := range KnownPathVars {
			fmt.Println(knownVar.Name)
		}
		return
	}
	if cword == 1 {
		for _, command := range Commands {
			fmt.Println(command.Name, "")
		}
	}
}

type Command struct {
	Name string
	Func func()
	Help string
}

var Commands = []Command{}

func initCommands() {
	Commands = []Command{
		Command{"ls", cmdLs,
			"List path entries (in order from first to last)"},
		Command{"ls-names", cmdLsNames,
			"List all files in path (names only)"},
		Command{"ls-files", cmdLsFiles,
			"List all files in path (full pathnames)"},
		Command{"run-files", cmdRunFiles,
			"Run program, feeding it filenames on stdin"},
		Command{"put-first", cmdPutFirst,
			"Add or move the given entry to the beginning of the path"},
		Command{"put-last", cmdPutLast,
			"Add or move the given entry to the end of the path"},
		Command{"rm", cmdRm,
			"Remove path entries (you'll be asked for each entry)"},
		Command{"which", cmdWhich,
			"See which file matches first in path"},
		Command{"shadow", cmdShadow,
			"Show name conflicts"},
		Command{"doctor", cmdDoctor,
			"Find potential path problems"},
		Command{"edit", cmdEdit,
			"Edit the path in EDITOR or another program"},
		Command{"export", cmdExport,
			"Generate an export statement in shell syntax"},
		Command{"activate", cmdActivate,
			"Try this in your shell: eval $(pathy activate)"},
		Command{"version", cmdVersion,
			"Show version information"},
	}
}

func cmdVersion() {
	fmt.Printf("%s %s\n", PROGNAME, PROGVERSION)
}

func cmdHelp() {
	fmt.Println("This is " + PROGNAME + ", helping you work with PATH and similar environment variables.")
	fmt.Println("Try `man " + PROGNAME + "` for a complete guide.")
	fmt.Println()
	for _, command := range Commands {
		fmt.Printf("%s %-12s %s\n", PROGNAME, command.Name, command.Help)
	}
	os.Exit(1)
}

func commandFuncByName(name string) func() {
	if name == "complete" {
		return cmdComplete
	}
	if name == "help" {
		return cmdHelp
	}
	for _, command := range Commands {
		if command.Name == name {
			return command.Func
		}
	}
	return cmdHelp
}

func main() {
	initKnownPathVars()
	initCommands()
	flag.StringVar(&PathVar, "V", "PATH", "environment variable to use")
	flag.Parse()
	if flag.NArg() == 0 {
		cmdHelp()
	}
	commandFuncByName(flag.Arg(0))()
}
