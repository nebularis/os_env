%% Copyright (c) 2011 Nebularis.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
-module(os_env).

-compile({no_auto_import,[get/1]}).

-include("os_env.hrl").
-export_type([arch/0, library/0]).

-export([environment_variables/0]).
-export([inspect_os/0, home_dir/0, get/1, get/2]).
-export([detect_os_arch/1, detect_long_bit/1]).
-export([locate_escript/1, default_escript_exe/0]).
-export([find_executable/1, find_executable/2]).
-export([executable_name/1, library_path_env/1, path_sep/1]).
-export([locate_library/2, detect_arch/1, load_path/1]).
-export([code_dir/0, relative_path/1, trim_cmd/1,
         cached_filename/1, root_dir/0, username/0]).

environment_variables() ->
    [ pair(Var) || Var <- os:getenv() ].

inspect_os() ->
    case os:type() of
        {unix, _} ->
            OS = uname("-s"),
            Vsn = os_vsn(),
            {OS, Vsn};
        {win32, _} ->
            {windows, unknown}
    end.

locate_library(Path, Lib) ->
    case filelib:fold_files(Path, Lib, true,
                            fun(F, Acc) -> [F|Acc] end, []) of
        [] ->
            undefined;
        [LibFile|_] ->
            #library{ path=Path, lib=LibFile, arch=detect_arch(LibFile) }
    end.

load_path(Path) ->
    {ENV, PathSep} = case os:type() of
        {win32,_} ->
            {"PATH", ";"};
        {unix,darwin} ->
            {"DYLD_LIBRARY_PATH", ":"};
        _ ->
            {"LD_LIBRARY_PATH", ":"}
    end,
    NewPath = case os:getenv(ENV) of
        false ->
            Path;
        Existing ->
            Parts = string:tokens(Existing, PathSep),
            string:join([Path | Parts], PathSep)
    end,
    {ENV, NewPath}.

%% TODO: make this work across the board...
library_path_env({windows, _})  -> "LIB";
library_path_env({darwin, _})   -> "DYLD_LIBRARY_PATH";
library_path_env(_)             -> "LD_LIBRARY_PATH".

path_sep({windows,_}) -> ";";
path_sep(_)           -> ":".

locate_escript(undefined) ->
    default_escript_exe();
locate_escript(ErlPath) ->
    BinDir = filename:join(ErlPath, "bin"),
    case find_executable("escript", BinDir) of
        false ->
            locate_escript(undefined);
        Exe ->
            Exe
    end.

default_escript_exe() ->
    {default, find_executable("escript",
                    filename:join(code:root_dir(), "bin"))}.

find_executable(Exe) ->
    find_executable(Exe, undefined).

find_executable(Exe, undefined) when is_list(Exe) ->
    os:find_executable(executable_name(Exe));
find_executable(Exe, Path) when is_list(Exe) andalso is_list(Path) ->
    os:find_executable(executable_name(Exe), Path).

executable_name(Exe) ->
    case os:type() of
        {win32,_} ->
            case lists:suffix(".bat", Exe) of
                true -> Exe;
                false ->
                    case lists:suffix(".exe", Exe) of
                        true ->
                            Exe;
                        false ->
                            string:join([Exe, "exe"], ".")
                    end
            end;
        _ ->
            Exe
    end.

detect_arch(LibPath) ->
    grep_for_arch(trim_cmd(os:cmd("file " ++ LibPath))).

detect_os_arch({windows,_}) ->
    %% TODO: handle on windows
    'x86';
detect_os_arch(_) ->
    grep_for_arch(uname("-a")).

detect_long_bit({windows,_}) ->
    %% TODO: fix on windows
    32;
detect_long_bit(_) ->
    list_to_integer(trim_cmd(os:cmd("getconf LONG_BIT"))).

grep_for_arch(String) ->
    case re:run(String, "(64-bit|x86_64|ia64|amd64)", [{capture,first,list}]) of
        {match, [_M|_]} -> 'x86_64';
        _ ->
            case re:run(String, "(32-bit|i386|i486|i586|i686|x86)",
                        [{capture,first,list}]) of
                {match, [_|_]} ->
                    %% TODO: deal with ia32 and amd32
                    'x86'
            end
    end.

os_vsn() ->
    [ list_to_integer(I) || I <- string:tokens(uname("-r"), ".") ].

uname(Flag) ->
    trim_cmd(os:cmd("uname " ++ Flag)).

username() ->
    case os:type() of
        {win32, _} ->
            erlang:hd(re:split(trim_cmd(os:cmd("whoami /UPN")), "@", []));
        _ ->
            trim_cmd(os:cmd("whoami"))
    end.

trim_cmd(Output) ->
    %% TODO: bootstrap most of the functions in this module at load time....
    case os:type() of
        {win32, _} ->
            string:strip(Output, right, $\n) -- [$\r];
        _ ->
            string:strip(Output, right, $\n)
    end.

code_dir() ->
    case os:getenv("ERL_LIBS") of
        false -> code:lib_dir();
        Path  -> Path
    end.

cached_filename(Name) ->
    relative_path(["build", "cache", Name]).

home_dir() ->
    {ok, [[HomeDir]]} = init:get_argument(home),
    HomeDir.

get(Var) when is_atom(Var) ->
    ?MODULE:get(atom_to_list(Var));
get(Var) when is_list(Var) ->
    os:getenv(string:to_upper(Var)).

get(Var, Default) when is_atom(Var) ->
    ?MODULE:get(string:to_upper(atom_to_list(Var)), Default);
get(Var, Default) ->
    case os:getenv(Var) of
        false -> Default;
        Val -> Val
    end.

root_dir() ->
    %% TODO: use some other mechanism besides the process dictionary for this...
    case erlang:get(standalone) of
        undefined ->
            filename:dirname(escript:script_name());
        _ ->
            {ok, Cwd} = file:get_cwd(),
            filename:dirname(Cwd)
    end.

relative_path(SuffixList) ->
    filename:absname(filename:join(root_dir(), filename:join(SuffixList))).

pair(Var) ->
    [A, B] = re:split(Var, "=", [{return,list},{parts,2}]),
    {list_to_atom(string:to_lower(A)), B}.

