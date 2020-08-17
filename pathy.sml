(* Copyright 2020 Lassi Kortela *)
(* SPDX-License-Identifier: ISC *)

exception PathyError of string;

val PROGNAME = "pathy"
val PROGVERSION = "0.1.0"

fun genericSort (equal, less, xs) =
    let fun insert (x, []) = [x]
          | insert (x, (y::ys)) =
            if equal (x, y) then (y::ys)
            else if less (x, y) then (x::y::ys)
            else (y::(insert (x, ys)))
        fun loop [] = []
          | loop (x::xs) = insert (x, (loop xs))
    in loop xs end;

fun sort xs =
    genericSort ((fn (a, b) => false), (fn (a, b) => a < b), xs);
fun sortLess (xs, less) =
    genericSort ((fn (a, b) => false), less, xs);
fun sortUniq xs: string list =
    genericSort ((fn (a, b) => a = b), (fn (a, b) => a <= b), xs);

fun joinPath (dir, name) = dir ^ "/" ^ name;
fun printLine s = print (s ^ "\n");

fun cleanDir dir = dir;

fun printToFd3 s =
    (Posix.IO.writeVec ((Posix.FileSys.wordToFD (SysWord.fromInt 3)),
                        (Word8VectorSlice.full (Byte.stringToBytes s)));
     ())
    handle OS.SysErr (_, errno) =>
           if errno = SOME Posix.Error.badf then
               printLine "file descriptor 3 is not open"
           else
               ();

fun getExecutableAbsPath () =
    let val bin = CommandLine.name () in
        if String.isPrefix "/" bin then
            bin
        else
            raise PathyError "Program name is not an absolute path /"
    end;

fun getEnvOrBlank envar = Option.getOpt ((OS.Process.getEnv envar), "");

val getRawPath = getEnvOrBlank;

fun getTheRawPathList sepChar envar =
    String.fields (fn c => c = sepChar) (getRawPath envar);

fun getRawPathList () =
    getTheRawPathList #":" "PATH";

fun getPathList () = getRawPathList ();

fun quotedPathFromPathList dirs =
    String.concatWith ":" dirs;

fun exportFromPathList dirs =
    let val pathVar = "PATH"
    in "export " ^ pathVar ^ "=" ^ (quotedPathFromPathList dirs) ^ "\n" end;

fun printExport dirs = print (exportFromPathList dirs);
fun printExportToFd3 dirs = printToFd3 (exportFromPathList dirs);

fun anySubMatch goal [] = false
  | anySubMatch goal (cand :: cands) =
    (String.isSubstring cand goal) orelse (anySubMatch goal cands)
and anyMatch goal [] = true
  | anyMatch goal cands = anySubMatch goal cands;

fun lines strings = (String.concatWith "\n" strings) ^ "\n";

fun getActivateCommand bin =
    lines ["_pathy_bin=" ^ bin,
           "",
           "pathy() {",
           "    exec 4>&1",
           "    IFS= _pathy_fd3=$($_pathy_bin \"$@\" 3>&1 >&4) || return",
           "    eval \"$_pathy_fd3\"",
           "    unset _pathy_fd3",
           "}",
           "",
           "_pathy_complete() {",
           "    IFS=$'\\n' COMPREPLY=($(compgen -W" ^
           " \"$($_pathy_bin complete " ^
           " \"$COMP_CWORD\"" ^
           " \"${COMP_WORDS[@]}\")\" -- \"${COMP_WORDS[COMP_CWORD]}\"))",
           "}",
           "",
           "complete -o nospace -F _pathy_complete pathy"];

fun lsFilesDir dirPath cands =
    let val d = OS.FileSys.openDir dirPath
    in
        let fun loop acc =
                case OS.FileSys.readDir d of
                    NONE => acc
                  | SOME name =>
                    loop (if anyMatch name cands then
                              name :: acc
                          else
                              acc)
        in
            let val acc = loop [] in
                (OS.FileSys.closeDir d; acc)
            end
        end
    end
    handle OS.SysErr (msg, eno) => [];

fun printPathList (pathList) =
    List.app printLine pathList;

fun filterPathList args pathList =
    List.filter (fn dir => anyMatch dir args)
                pathList;

fun foldAllFiles (filters, cons, state) =
    let fun outer (state, []) = state
          | outer (state, dir::dirs) =
            outer ((inner (state, dir, (lsFilesDir dir filters))), dirs)
        and inner (state, dir, []) = state
          | inner (state, dir, name::names) =
            inner ((cons (dir, name, state)), dir, names)
    in outer (state, (getRawPathList ())) end;

fun forAllFiles (filters, visit) =
    foldAllFiles (filters,
                  (fn (dir, name, _) => (visit (dir, name); ())),
                  ());

fun cmdLs(args: string list) =
    printPathList (filterPathList args (getRawPathList ()));

fun cmdLsNames(args: string list) =
    List.app printLine
             (sortUniq (foldAllFiles (args,
                                      (fn (dir, name, names)
                                          => name :: names),
                                      [])));

fun cmdLsFiles(args: string list) =
    List.app printLine
             (sortUniq (foldAllFiles (args,
                                      (fn (dir, name, files)
                                          => (joinPath (dir, name)) :: files),
                                      [])));

fun cmdRunFiles(args: string list) = ();

fun cmdPutFirst(args: string list) =
    printExportToFd3 ((map (op cleanDir) args) @ (getPathList ()));

fun cmdPutLast(args: string list) =
    printExportToFd3 ((getPathList ()) @ (map (op cleanDir) args));

fun groupBy key xs =
    let fun loop (gs, g, []) = gs
          | loop (gs, [], (x::xs)) = loop (gs, [x], xs)
          | loop (gs, (ga::g), (x::xs)) = if key x = key ga then
                                              loop (gs, (x::ga::g), xs)
                                          else
                                              loop (((ga::g)::gs), [x], xs)
    in loop ([], [], xs) end;

fun getGroups filters =
    groupBy (fn a => #2 a)
            (sortLess ((foldAllFiles
                            (filters,
                             (fn (dir, name, pairs)
                                 => ((dir, name) :: pairs)),
                             [])),
                       (fn (a, b) => (#2 a) < (#2 b))));

fun cmdWhich(args: string list) =
    case getGroups []
     of groups =>
        List.app (fn goalName =>
                     List.app (fn group =>
                                  case List.nth (group, 0)
                                   of (dir, name) =>
                                      if name = goalName then
                                          (printLine (joinPath (dir, name)))
                                      else
                                          ())
                              groups)
                 args;

fun cmdShadow(args: string list) =
    List.app (fn group =>
                 ((List.app (fn (dir, name) => printLine (joinPath (dir, name)))
                            group);
                  (printLine "")))
             (List.filter (fn group => (List.length group) > 1)
                          (getGroups args));

fun cmdDoctor(args: string list) = ();

val defaultEditor = "vi";

fun getEditor () =
    case OS.Process.getEnv "EDITOR" of
        SOME value => if value = "" then defaultEditor else value
      | NONE => defaultEditor;

fun writeTextFile (file, string) =
    case TextIO.openOut file
     of s => (TextIO.output (s, string);
              TextIO.closeOut s);

fun readTextFile file =
    case TextIO.openIn file
     of s => case TextIO.inputAll s
              of string => ((TextIO.closeIn s); string);

fun trimWhitespace string =
    let val n = String.size string
        fun left a =
            if a = n then ""
            else if Char.isSpace (String.sub (string, a)) then left (a + 1)
            else right a n
        and right a b =
            if b = a then ""
            else if Char.isSpace (String.sub (string, (b - 1))) then
                right a (b - 1)
            else String.substring (string, a, (b - a))
    in left 0 end;

fun stringLines string = String.fields (fn c => c = #"\n") string;

(* TODO: case insensitive *)
fun confirm prompt =
    case prompt ^  "? [yN] "
     of fullPrompt =>
        let fun loop () =
                ((print fullPrompt);
                 case (TextIO.inputLine TextIO.stdIn)
                  of NONE => loop ()
                   | SOME line => case trimWhitespace line
                                   of "yes" => true
                                    | "no" => false
                                    | "y" => true
                                    | "n" => false
                                    | _ => loop ());
        in loop () end;

fun cmdEdit (args: string list) =
    let val pathVar = "PATH"
        val oldPath = getPathList ()
        val editor = getEditor ()
        val tempfile = OS.FileSys.tmpName ()
    in writeTextFile (tempfile, (lines (oldPath)));
       let val status = OS.Process.system (editor ^ " " ^ tempfile) in
           if not (OS.Process.isSuccess status) then
               printLine "Failed"
           else
               let val newPath =
                       (List.filter (fn line => line <> "")
                                    (List.map (op trimWhitespace)
                                              (stringLines
                                                   (readTextFile tempfile))))
               in
                   if newPath = oldPath then
                       printLine "No changes."
                   else
                       (printPathList newPath;
                        print "\n";
                        if confirm ("Use this new " ^ pathVar) then
                            printLine (pathVar ^ " changed.")
                        else
                            printLine (pathVar ^ " not changed."))
               end
       end
    end;

fun cmdExport(args: string list) = printExport (getPathList ());

fun cmdActivate(args: string list) =
    print (getActivateCommand (getExecutableAbsPath ()));

fun cmdVersion(args: string list) =
    let val os = MLton.Platform.OS.toString (MLton.Platform.OS.host)
        val ar = MLton.Platform.Arch.toString (MLton.Platform.Arch.host)
    in printLine (PROGNAME ^ " " ^ PROGVERSION ^ " (" ^ os ^ ", " ^ ar ^ ")")
    end;

fun listMax ints = List.foldl (op Int.max) 0 ints;

fun commands () = [
    ("ls", cmdLs,
     "List path entries (in order from first to last)"),
    ("put-first", cmdPutFirst,
     "Add or move the given entry to the beginning of the path"),
    ("put-last", cmdPutLast,
     "Add or move the given entry to the end of the path"),
    ("ls-names", cmdLsNames,
     "List all files in path (names only)"),
    ("ls-files", cmdLsFiles,
     "List all files in path (full pathnames)"),
    ("run-files", cmdRunFiles,
     "Run program, feeding it filenames on stdin"),
    ("which", cmdWhich,
     "See which file matches first in path"),
    ("shadow", cmdShadow,
     "Show name conflicts"),
    ("doctor", cmdDoctor,
     "Find potential path problems"),
    ("edit", cmdEdit,
     "Edit the path in $EDITOR"),
    ("export", cmdExport,
     "Show an export statement in shell syntax"),
    ("activate", cmdActivate,
     "Try in your shell: eval \"$($(which pathy) activate)\""),
    ("version", cmdVersion,
     "Show version information"),
    ("help", cmdHelp,
     "Show this help")
]
and getUsageMessage () =
    "This is " ^ PROGNAME ^ ", helping you work with" ^
    " PATH and similar environment variables." ^ "\n" ^
    "Try `man " ^ PROGNAME ^ "` for a complete guide." ^ "\n" ^
    "\n" ^
    let val commandNames = List.map (fn x => #1 x) (commands ())
        val width = listMax (List.map String.size commandNames)
    in String.concat (List.map (fn (name, _, help) =>
                                   PROGNAME ^ " " ^
                                   (StringCvt.padRight #" " width name) ^
                                   "  " ^ help ^ "\n")
                               (commands ()))
    end
and usage () =
    print (getUsageMessage ())
and cmdHelp (args: string list) =
    usage ();

fun commandNamed name =
    let
        fun search [] = NONE
          | search (cmd  :: cmds) =
            (case cmd of
                 (cmdName, _, _) =>
                 if cmdName = name then
                     SOME cmd
                 else
                     search cmds)
    in
        search (commands ())
    end;

fun mainWithArgs [] = cmdHelp []
  | mainWithArgs (cmdName :: cmdArgs) =
    case commandNamed cmdName of
        NONE => usage ()
      | SOME (_, cmd, _) => cmd cmdArgs;

fun main () = mainWithArgs (CommandLine.arguments ());

main ();
