-module(telemetry_registry).

%% API
-export([discover_all/0,
         discover_all/1,
         list_events/0,
         spannable_events/0]).

-define(KEY, ?MODULE).

-type application() :: atom().
-type event() :: {telemetry:event_name(), module(), event_meta()}.
-type event_description() :: binary().
-type event_measurements() :: binary().
-type event_metadata() :: binary().
-type event_definition() :: #{
                              event := telemetry:event_name(),
                              description := event_description(),
                              measurements := event_measurements(),
                              metadata := event_metadata()
                             }.
-type event_meta() :: #{
                              description := event_description(),
                              measurements := event_measurements(),
                              metadata := event_metadata()
                             } | #{}.
-type spannable_event() :: {telemetry:prefix(), [atom()]}.

-export_type([application/0,
              event/0,
              event_definition/0,
              event_description/0,
              event_measurements/0,
              event_metadata/0,
              event_meta/0,
              spannable_event/0
             ]).


%% @doc Returns a list of all registered events.
-spec list_events() -> [event()].
list_events() ->
    persistent_term:get(?KEY, []).

%% @doc Returns a list of spannable events.
-spec spannable_events() -> [spannable_event()].
spannable_events() ->
    AllEvents = list_events(),
    ReversedEvents = reverse_events(AllEvents),
    Filtered = filter_events(ReversedEvents),
    event_spans(Filtered).

-spec reverse_events([event()]) -> [telemetry:event_name()].
reverse_events(Events) ->
    [lists:reverse(Event) || {Event, _, _} <- Events].

-spec filter_events([telemetry:event_name()]) -> [telemetry:event_name()].
filter_events(Events) ->
    lists:filter(fun([Suffix | _]) -> lists:member(Suffix, [start, stop, exception]) end, Events).

-spec event_spans([telemetry:event_name()]) -> [spannable_event()].
event_spans(Events) ->
    {_, SpannableEvents} = lists:foldl(fun([start | Event], {AllEvents, Spans}) ->
                        case lists:member([stop | Event], AllEvents) of
                            true ->
                                SpanPrefix = lists:reverse(Event),
                                case lists:member([exception | Event], AllEvents) of
                                    true ->
                                        UpdatedSpans = maps:put(SpanPrefix, [start, stop, exception], Spans),
                                        {AllEvents, UpdatedSpans};
                                    false ->
                                        {AllEvents, maps:put(SpanPrefix, [start, stop], Spans)}
                                end;
                            false ->
                                {AllEvents, Spans}
                        end;
                   (_, Acc) ->
                        Acc
    end, {Events, #{}}, Events),
    maps:to_list(SpannableEvents).

%% @doc Discover all declared telemetry events in the application it is invoked from and all child applications.
%% This would normally be invoked during application startup.
-spec discover_all() -> ok.
discover_all() ->
    discover_all([App || {App, _, _} <- application:loaded_applications()]).

%% @doc Discover all declared telemetry events in the given application and its child applications. This is
%% typically used in libraries leveraging <pre>telemetry_registry</pre> where it would be necessary for the user
%% to define what the root application is, e.g. in tracing bridge libraries.
-spec discover_all(application() | [application()]) -> ok.
discover_all(Applications) ->
    Events = maps:keys(maps:from_list([{Event, []} || Event <- gather_all_events(Applications)])),
    persistent_term:put(?KEY, Events).

-spec gather_all_events([application()] | application()) -> [event()].
gather_all_events(Applications) when is_list(Applications) ->
    lists:flatmap(fun gather_all_events/1, Applications);
gather_all_events(Application) ->
    Applications = child_applications(Application),
    lists:flatmap(fun gather_application_events/1, [Application | Applications]).

-spec child_applications(application()) -> [application()].
child_applications(Application) ->
    {ok, ChildApplications} = application:get_key(Application, applications),
    {ok, ChildIncludedApplications} = application:get_key(Application, included_applications),
    ChildApplications ++ ChildIncludedApplications.

-spec gather_application_events(application()) -> [event()].
gather_application_events(Application) ->
    case application:get_key(Application, modules) of
        {ok, Modules} -> lists:flatmap(fun events_for_module/1, Modules);
        _ -> []
    end.

-spec events_for_module(atom()) -> [telemetry:event_name() | event_definition()].
events_for_module(Module) ->
    Attributes = case code:is_loaded(Module) of
                     {file, _} -> Module:module_info(attributes);
                     _ ->
                         case code:get_object_code(Module) of
                             {Module, Binary, _} ->
                                 {ok, {_, [{attributes, Data}]}} = beam_lib:chunks(Binary, [attributes]),
                                 Data;
                             _ -> []
                         end
                 end,
    Events = lists:flatten(proplists:get_all_values(telemetry_event, Attributes)),
    [{EventName, Module, EventMeta} || {EventName, EventMeta} <- [assert_event(Event) || Event <- Events]].

-spec assert_event(term()) -> {telemetry:event_name(), event_meta()} | no_return().
assert_event(Event) when is_map(Event) ->
    {EventName, EventMeta} = maps:take(event, Event),
    assert_event_name(EventName),
    assert_description(EventMeta),
    assert_measurements(EventMeta),
    assert_metadata(EventMeta),
    {EventName, EventMeta};
assert_event(Term) ->
    erlang:error(badarg, Term).

-spec assert_event_name(term()) -> ok | no_return().
assert_event_name([_ | _] = List) ->
    case lists:all(fun erlang:is_atom/1, List) of
        true ->
            ok;
        false ->
            erlang:error(badarg, List)
    end;
assert_event_name(Term) ->
    erlang:error(badarg, Term).

-spec assert_description(term()) -> ok | no_return().
assert_description(#{description := Description}) when is_binary(Description) ->
    ok;
assert_description(Term) ->
    erlang:error(badarg, Term).

-spec assert_measurements(term()) -> ok | no_return().
assert_measurements(#{measurements := Measurements}) when is_binary(Measurements) ->
    ok;
assert_measurements(Term) ->
    erlang:error(badarg, Term).

-spec assert_metadata(term()) -> ok | no_return().
assert_metadata(#{metadata := Metadata}) when is_binary(Metadata) ->
    ok;
assert_metadata(Term) ->
    erlang:error(badarg, Term).
