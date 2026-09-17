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
    %% rapier_lab-d00: MobRapier.Physics's Rustler on_load calls
    %% Application:app_dir(mob_rapier), which requires the app's .app file
    %% to be loaded (not started — just loaded). start_clean's -boot only
    %% loads kernel + stdlib, so any hex/path dep whose module is called
    %% via Rustler must be loaded explicitly before its beam gets touched.
    step(5, fun() -> application:load(mob_rapier) end),
    step(6, fun() -> 'Elixir.RapierLab.MobApp':start() end),
    timer:sleep(infinity).

step(N, Fun) ->
    mob_nif:log("step " ++ integer_to_list(N) ++ " starting"),
    Result = (catch Fun()),
    mob_nif:log(
        "step " ++ integer_to_list(N) ++ " => " ++
            lists:flatten(io_lib:format("~p", [Result]))
    ).
