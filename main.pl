:- use_module(library(charsio)).
:- use_module(library(dcgs)).
:- use_module(library(files)).
:- use_module(library(format)).
:- use_module(library(iso_ext)).
:- use_module(library(lists)).
:- use_module(library(pio)).
:- use_module(library(ordsets)).
:- use_module(library(time)).

:- use_module(teruel/teruel).
:- use_module(djota/djota).

run(ConfigFile) :-
    portray_clause(doclog(1, 0, 0)),    
    atom_chars(ConfigFileA, ConfigFile),
    consult(ConfigFileA),
    generate_nav(Nav),
    generate_footer(Footer),
    Sections = ["nav"-Nav, "footer"-Footer],
    generate_page_docs(Sections),
    generate_readme(Sections),
    halt.

run(_) :-
    portray_clause(error_running_doclog),
    halt(1).

generate_nav(NavHtml) :-
    source_folder(SF),
    path_segments(SF, SFSG),
    subnav(SFSG, ".", Nav),
    member("nav"-NavHtml, Nav).

subnav(Base, Dir, ["name"-Dir, "nav"-Nav, "type"-"dir"]) :-    
    append(Base, [Dir], DirSg),
    path_segments(RealDir, DirSg),
    directory_exists(RealDir),
    directory_files(RealDir, Files),
    files_not_omitted_files(RealDir, Files, FilesReal),
    sort(FilesReal, FilesSorted),
    maplist(subnav(DirSg), FilesSorted, Items),
    render("nav.html", ["items"-Items], Nav).

subnav(Base, File, ["name"-Name, "link"-['/'|Link], "type"-"file"]) :-
    append(Base, [File], FileSg),
    append(Name, ".pl", File),
    path_segments(FilePath, FileSg),
    file_exists(FilePath),
    append(_, ["."|LinkSg], FileSg),
    path_segments(Link0, LinkSg),
    append(Link1, ".pl", Link0),
    append(Link1, ".html", Link).

files_not_omitted_files(_, [], []).
files_not_omitted_files(Base, [X|Xs], Ys) :-
    source_folder(SF),
    findall(FullOmitFile,(
		omit(Omit),
		member(OmitFile, Omit),
		append(SF, ['/', '.', '/'|OmitFile], FullOmitFile)
	    ), OmitFiles),
    append(Base, ['/'|X], File),
    (
	member(File, OmitFiles) ->
	Ys = Ys0
    ;   Ys = [X|Ys0]
    ),
    files_not_omitted_files(Base, Xs, Ys0).

generate_footer(Footer) :-
    current_time(T),
    phrase(format_time("%b %d %Y", T), Time),
    render("footer.html", ["time"-Time], Footer).

generate_readme(Sections) :-
    readme_file(ReadmeFile),
    project_name(ProjectName),
    output_folder(OutputFolder),
    path_segments(OutputFolder, OutputFolderSg),
    append(OutputFolderSg, ["index.html"], OutputFileSg),
    path_segments(OutputFile, OutputFileSg),
    phrase_from_file(seq(ReadmeMd), ReadmeFile),
    djot(ReadmeMd, ReadmeHtml),
    Vars0 = ["project_name"-ProjectName, "readme"-ReadmeHtml],
    append(Vars0, Sections, Vars),
    render("index.html", Vars, IndexHtml),
    phrase_to_file(seq(IndexHtml), OutputFile).

generate_page_docs(Sections) :-
    source_folder(DocsFolder),
    output_folder(OutputFolder),    
    make_directory(OutputFolder),
    directory_files(DocsFolder, Files),
    path_segments(DocsFolder, Base),
    path_segments(OutputFolder, Output),
    append(Output, ["search-index.json"], SearchIndexSg),
    path_segments(SearchIndex, SearchIndexSg),
    setup_call_cleanup(open(SearchIndex, write, SearchWriteStream),(
	format(SearchWriteStream, "[", []),
        maplist(process_file(Base, Output, Sections, SearchWriteStream), Files),
	format(SearchWriteStream, "{}]", [])
    ), close(SearchWriteStream)),	
    copy_file("doclog.css", Output),
    copy_file("doclog.js", Output).

process_file(Base, Output0, Sections, SearchWriteStream, File0) :-
    append(Base, [File0], FileSg),
    append(File1, ".pl", File0),
    append(File1, ".html", Output1),
    append(Output0, [Output1], OutputSg),
    path_segments(Output, OutputSg),
    path_segments(File, FileSg),
    file_exists(File),
    portray_clause(process_file(File)),
    open(File, read, FileStream),
    read_term(FileStream, Term, []),
    (
	Term = (:- module(ModuleName, PublicPredicates)) ->
	(
	    predicates_clean(PublicPredicates, PublicPredicates1, Ops),
	    document_file(File, Output, ModuleName, PublicPredicates1, Ops, Sections),
	    append_predicates_search_index(Output, PublicPredicates1, Ops, SearchWriteStream)
	)
    ;   true
    ),
    close(FileStream).
    

process_file(Base0, Output0, Sections, SearchWriteStream, Dir0) :-
    append(Base0, [Dir0], DirSg),
    append(Output0, [Dir0], Output),
    path_segments(Dir, DirSg),
    directory_exists(Dir),
    path_segments(OutputDir, Output),
    make_directory(OutputDir),
    directory_files(Dir, Files),
    maplist(process_file(DirSg, Output, Sections, SearchWriteStream), Files).

predicates_clean([], [], []).
predicates_clean([X|Xs], [X|Ys], Ops) :-
    X \= op(_,_,_),
    predicates_clean(Xs, Ys, Ops).
predicates_clean([X|Xs], Ys, [X|Ops]) :-
    X = op(_,_,_),
    predicates_clean(Xs, Ys, Ops).
    

append_predicates_search_index(Output, PublicPredicates, Ops, SearchWriteStream) :-
    output_folder(OF),
    append(OF, Relative, Output),
    maplist(append_search_index(Relative, SearchWriteStream, Ops), PublicPredicates).

append_search_index(Output, SearchWriteStream, Ops, Predicate) :-
    predicate_string(Predicate, Ops, PredicateString),
    phrase(escape_js(PredicateStringSafe), PredicateString),
    format(SearchWriteStream, "{\"link\": \"~s#~s\", \"predicate\": \"~s\"},", [Output, PredicateStringSafe, PredicateStringSafe]).

append_search_index(Output, SearchWriteStream, op(_,_,Operator)) :-
    atom_chars(Operator, NameUnsafe),
    phrase(escape_js(Name), NameUnsafe),
    format(SearchWriteStream, "{\"link\": \"~s\", \"predicate\": \"~s\"},", [Output, Name]).

escape_js([]) --> [].
escape_js([X|Xs]) -->
    [X],
    {
	X \= (\)
    },
    escape_js(Xs).
escape_js(Xs) -->
    "\\",
    escape_js(Xs0),
    { append("\\\\", Xs0, Xs) }.

document_file(InputFile, OutputFile, ModuleName, PublicPredicates, Ops, Sections) :-
    maplist(document_predicate(InputFile, Ops), PublicPredicates, Predicates),
    phrase_from_file(module_description(ModuleDescriptionMd), InputFile),
    djot(ModuleDescriptionMd, ModuleDescriptionHtml),
    atom_chars(ModuleName, ModuleNameStr),
    project_name(ProjectName),
    source_folder(SF),
    websource(WebSourceBase),
    append(SF, ExtraFile, InputFile),
    append(['/'|LibraryUse], ".pl", ExtraFile),
    append(WebSourceBase, ExtraFile, WebSource),
    Vars0 = [
	"project_name"-ProjectName,
	"module_name"-ModuleNameStr,
	"module_description"-ModuleDescriptionHtml,
	"predicates"-Predicates,
	"websource"-WebSource,
	"library"-LibraryUse
    ],
    append(Vars0, Sections, Vars),
    render("page.html", Vars, HtmlOut),
    phrase_to_file(seq(HtmlOut), OutputFile).

module_description(X) -->
    ... ,
    "/**",
    seq(X),
    "*/",
    ... .

module_description("No description") -->
    ... .

predicate_string(Predicate, Ops, PredicateString) :-
    Predicate = PN/PA,
    member(op(_, _, PN), Ops),
    phrase(format_("(~a)/~d", [PN, PA]), PredicateString).

predicate_string(Predicate, Ops, PredicateString) :-
    Predicate = PN/_PA,
    \+ member(op(_, _, PN), Ops),
    phrase(format_("~q", [Predicate]), PredicateString).

predicate_string(Predicate, Ops, PredicateString) :-
    Predicate = _PN//_PA,
    phrase(format_("~q", [Predicate]), PredicateString).

% First try to extract description based on name and arity, if not, fallback to extremely simple description
document_predicate(InputFile, Ops, Predicate, ["predicate"-PredicateString, "name"-Name, "description"-Description]) :-
    portray_clause(documenting(Predicate)),
    predicate_string(Predicate, Ops, PredicateString),
    (
	(
	    phrase_from_file(predicate_documentation(Predicate, Name, DescriptionMd), InputFile),
	    djot(DescriptionMd, Description)
	)
    ;	document_predicate(Predicate, Ops, ["name"-Name, "description"-Description])
    ).

document_predicate(Predicate, Ops, ["name"-Name, "description"-Description]) :-
    predicate_string(Predicate, Ops, Name),
    Description = "".

predicate_documentation(Predicate, Name, Description) -->
    ... ,
    "%% ",
    predicate_name(Predicate, Name),
    "\n%", whites, "\n",
    predicate_description(Description),
    ... .

predicate_name(PredicateName/0, Name) -->
    {
	atom_chars(PredicateName, NameCs)
    },
    NameCs,
    seq(RestCs),
    {
	append(NameCs, RestCs, Name)
    }.

predicate_name(PredicateName/Arity, Name) -->
    {
	atom_chars(PredicateName, NameCs)
    },
    NameCs,
    "(",
    seq(Args),
    ")",
    !,
    {
	Commas is Arity - 1,
	phrase(commas(Commas), Args)
    },
    seq(RestCs),
    {
	phrase((NameCs,"(",seq(Args),")",seq(RestCs)), Name)
    }.

predicate_name(PredicateName//0, Name) -->
    {
	atom_chars(PredicateName, NameCs)
    },
    NameCs,"//",
    seq(RestCs),
    {
	phrase((NameCs, RestCs, "//"), Name)
    }.

predicate_name(PredicateName//Arity, Name) -->
    {
	atom_chars(PredicateName, NameCs)
    },
    NameCs,
    "(",
    seq(Args),
    ")//",
    !,
    {
	Commas is Arity - 1,
	phrase(commas(Commas), Args)
    },
    seq(RestCs),
    {
	phrase((NameCs,"(",seq(Args),")//",seq(RestCs)), Name)
    }.
    

predicate_description(Description) -->
    "% ", seq(Line), "\n",
    predicate_description(Description0),
    {
	append(Line, ['\n'|Description0], Description)
    }.
predicate_description(Description) -->
    "%", whites, "\n",
    predicate_description(Description0),
    {
	Description = ['\n'|Description0]
    }.
predicate_description("") --> [].

whites --> [].
whites --> " ", whites.
whites --> "\t", whites.

commas(0) -->
    seq(X),
    {
	\+ member(',', X)
    }.
commas(N) -->
    seq(X),
    {
	\+ member(',', X)
    },
    ",",
    commas(N0),
    {
	N is N0 + 1
    }.

dirs_only([F|Fs], Output, [F|FOs]) :-
    append(Output, [F], OutputFile),
    path_segments(File, OutputFile),
    directory_exists(File),
    dirs_only(Fs, Output, FOs).

dirs_only([F|Fs], Output, FOs) :-
    append(Output, [F], OutputFile),
    path_segments(File, OutputFile),    
    \+ directory_exists(File),
    dirs_only(Fs, Output, FOs).

dirs_only([], _, []).

string_without([X|Xs], Block) -->
    [X],
    {
	X \= Block
    },
    string_without(Xs, Block).

string_without([], Block) -->
    [X],
    {
	X = Block
    }.

string_without([], _) -->
    [].

copy_file(File, Output) :-
    append(Output, [File], OutputFileSg),
    path_segments(OutputFile, OutputFileSg),
    setup_call_cleanup(open(File, read, Stream),(
	get_n_chars(Stream, _, Css),
        phrase_to_file(seq(Css), OutputFile)),
        close(Stream)).
