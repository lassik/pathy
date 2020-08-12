(* Copyright 2020 Lassi Kortela *)
(* SPDX-License-Identifier: ISC *)

exception PathyError of string;

val PROGNAME = "pathy"
val PROGVERSION = "0.1.0"

fun cleanDir dir = dir;

fun printToFd3 s =
    (Posix.IO.writeVec ((Posix.FileSys.wordToFD (SysWord.fromInt 3)),
                        (Word8VectorSlice.full (Byte.stringToBytes s)));
     ())
    handle OS.SysErr (_, errno) =>
           if errno = SOME Posix.Error.badf then
               print "file descriptor 3 is not open\n"
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
    List.app (fn dir => print (dir ^ "\n"))
             pathList;

fun filterPathList args pathList =
    List.filter (fn dir => anyMatch dir args)
                pathList;

fun cmdLs(args: string list) =
    printPathList (filterPathList args (getRawPathList ()));

fun cmdLsNames(args: string list) =
    let fun loop [] = ()
          | loop (dir :: dirs) =
            (List.app (fn name => print (name ^ "\n"))
                      (lsFilesDir dir args);
             loop dirs)
    in loop (filterPathList args (getRawPathList ())) end;

fun cmdLsFiles(args: string list) =
    let fun loop [] = ()
          | loop (dir :: dirs) =
            (List.app (fn name => print (dir ^ "/" ^ name ^ "\n"))
                      (lsFilesDir dir args);
             loop dirs)
    in loop (filterPathList args (getRawPathList ())) end;

fun cmdRunFiles(args: string list) = ();

fun cmdPutFirst(args: string list) =
    printExportToFd3 ((map (op cleanDir) args) @ (getPathList ()));

fun cmdPutLast(args: string list) =
    printExportToFd3 ((getPathList ()) @ (map (op cleanDir) args));

fun cmdRm(args: string list) = ();

fun cmdWhich(args: string list) = ();

fun cmdShadow(args: string list) = ();

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
               print "Failed\n"
           else
               let val newPath =
                       (List.filter (fn line => line <> "")
                                    (List.map (op trimWhitespace)
                                              (stringLines
                                                   (readTextFile tempfile))))
               in
                   if newPath = oldPath then
                       print "No changes.\n"
                   else
                       (printPathList newPath;
                        print "\n";
                        if confirm ("Use this new " ^ pathVar) then
                            print (pathVar ^ " changed.\n")
                        else
                            print (pathVar ^ " not changed.\n"))
               end
       end
    end;

fun cmdExport(args: string list) = printExport (getPathList ());

fun cmdActivate(args: string list) =
    print (getActivateCommand (getExecutableAbsPath ()));

fun cmdVersion(args: string list) =
    print (PROGNAME ^ " " ^ PROGVERSION ^ " (" ^ "os" ^ ", " ^ "sml" ^ ")\n");

datatype COMMAND = Command of string * (string list -> unit) * string;

val commands = [
    Command ("ls", cmdLs,
             "List path entries (in order from first to last)"),
    Command ("ls-names", cmdLsNames,
             "List all files in path (names only)"),
    Command ("ls-files", cmdLsFiles,
             "List all files in path (full pathnames)"),
    Command ("run-files", cmdRunFiles,
             "Run program, feeding it filenames on stdin"),
    Command ("put-first", cmdPutFirst,
             "Add or move the given entry to the beginning of the path"),
    Command ("put-last", cmdPutLast,
             "Add or move the given entry to the end of the path"),
    Command ("rm", cmdRm,
             "Remove path entries (you'll be asked for each entry)"),
    Command ("which", cmdWhich,
             "See which file matches first in path"),
    Command ("shadow", cmdShadow,
             "Show name conflicts"),
    Command ("doctor", cmdDoctor,
             "Find potential path problems"),
    Command ("edit", cmdEdit,
             "Edit the path in EDITOR or another program"),
    Command ("export", cmdExport,
             "Generate an export statement in shell syntax"),
    Command ("activate", cmdActivate,
             "Try this in your shell: eval \"$($(which pathy) activate)\""),
    Command ("version", cmdVersion,
             "Show version information")
]

fun commandNamed name =
    let
        fun search [] = NONE
          | search (cmd  :: cmds) =
            (case cmd of
                 Command (cmdName, _, _) =>
                 if cmdName = name then
                     SOME cmd
                 else
                     search cmds)
    in
        search commands
    end;

fun listMax ints = List.foldl (op Int.max) 0 ints;
val commandNames = List.map (fn Command x => #1 x) commands;

fun getUsageMessage () =
    "This is " ^ PROGNAME ^ ", helping you work with" ^
    " PATH and similar environment variables." ^ "\n" ^
    "Try `man " ^ PROGNAME ^ "` for a complete guide." ^ "\n" ^
    "\n" ^
    let val width = listMax (List.map String.size commandNames)
    in
        String.concat (List.map (fn Command (cmdName, _, cmdHelp) =>
                                    PROGNAME ^ " " ^
                                    (StringCvt.padRight #" " width cmdName) ^
                                    "  " ^ cmdHelp ^ "\n")
                                commands)
    end;

fun usage () =
    print (getUsageMessage ());

fun mainWithArgs [] = usage ()
  | mainWithArgs (cmdName :: cmdArgs) =
    case commandNamed cmdName of
        NONE => usage ()
      | SOME (Command (_, cmd, _)) => cmd cmdArgs;

fun main () = mainWithArgs (CommandLine.arguments ());

main ();
