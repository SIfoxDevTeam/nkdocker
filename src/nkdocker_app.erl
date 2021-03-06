%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Carlos Gonzalez Florido.  All Rights Reserved.
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
%%
%% -------------------------------------------------------------------

%% @doc NkDOCKER OTP Application Module
-module(nkdocker_app).
-author('Carlos Gonzalez <carlosj.gf@gmail.com>').
-behaviour(application).

-export([start/0, start/2, stop/1]).

-include("nkdocker.hrl").
-include_lib("nklib/include/nklib.hrl").


-define(APP, nkdocker).

%% ===================================================================
%% Private
%% ===================================================================

%% @doc Starts NkDOCKER stand alone.
-spec start() -> 
    ok | {error, Reason::term()}.

start() ->
    case nklib_util:ensure_all_started(?APP, permanent) of
        {ok, _Started} ->
            ok;
        Error ->
            Error
    end.

%% @private OTP standard start callback
start(_Type, _Args) ->
    _ = code:ensure_loaded(nkdocker_protocol),
    {ok, Pid} = nkdocker_sup:start_link(),
    {ok, Vsn} = application:get_key(nkdocker, vsn),
    lager:notice("NkDOCKER v~s has started.", [Vsn]),
    get_config(),
    {ok, Pid}.


%% @private OTP standard stop callback
stop(_) ->
    ok.


%% @private
get_config() ->
    Proto = get_env(proto, tcp),
    ConnOpts1 = #{  
        host => get_env(host, "127.0.0.1"),
        port => get_env(port, case Proto of tcp -> 2375; tls -> 2376 end),
        proto => Proto,
        certfile => nkpacket_config:certfile(),
        keyfile => nkpacket_config:keyfile()
    },
    ConnOpts2 = case os:getenv("DOCKER_HOST") of
        false ->
            ConnOpts1;
        Host ->
            case nklib_parse:uris(Host) of
                [#uri{scheme=tcp, domain=Domain, port=Port}] ->
                    ConnOpts1#{host=>Domain, port=>Port, proto=>tcp};
                _  ->
                    ConnOpts1
            end
    end,
    ConnOpts3 = case 
        os:getenv("DOCKER_TLS") == "1" orelse
        os:getenv("DOCKER_TLS") == "true" orelse
        os:getenv("DOCKER_TLS_VERIFY") == "1" orelse
        os:getenv("DOCKER_TLS_VERIFY") == "true"
    of
        true -> ConnOpts2#{proto=>tls};
        false -> ConnOpts2
    end,
    ConnOpts4 = case os:getenv("DOCKER_CERT_PATH") of
        false -> 
            ConnOpts3;
        Path ->
            ConnOpts3#{
                certfile => filename:join(Path, "cert.pem"),
                keyfile => filename:join(Path, "key.pem")
            }
    end,
    case map_size(ConnOpts4) of
        0 -> ok;
        _ -> lager:notice("Detected Config: ~p", [ConnOpts4])
    end,
    application:set_env(?APP, conn_config, ConnOpts4).


%% @private
get_env(Key, Default) ->
    application:get_env(?APP, Key, Default).


