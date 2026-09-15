%% rapier_lab.erl — BEAM bootstrap for rapier_lab (thin-client Mob app).
-module(rapier_lab).
-export([start/0]).
%% The template's `catch Fun()` is deliberate (log-everything bootstrap);
%% silence OTP's deprecation warning rather than diverge from the shape.
-compile([nowarn_deprecated_catch]).

start() ->
    step(1, fun() -> application:start(compiler) end),
    step(2, fun() -> application:start(elixir) end),
    step(3, fun() -> application:start(logger) end),
    step(4, fun() -> mob_nif:platform() end),
    step(5, fun() -> 'Elixir.RapierLab.MobApp':start() end),
    timer:sleep(infinity).

step(N, Fun) ->
    mob_nif:log("step " ++ integer_to_list(N) ++ " starting"),
    Result = (catch Fun()),
    mob_nif:log(
        "step " ++ integer_to_list(N) ++ " => " ++
            lists:flatten(io_lib:format("~p", [Result]))
    ).
