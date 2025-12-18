[![EEF Observability WG project](https://img.shields.io/badge/EEF-Observability-black)](https://github.com/erlef/eef-observability-wg)
[![Hex.pm](https://img.shields.io/hexpm/v/telemetry_registry)](https://hex.pm/packages/telemetry_registry)

# Telemetry Registry

TelemetryRegistry is a library for Telemetry event declaration, discovery, and registration. Events
are declared using the module attribute `telemetry_event` and include a description of the event,
measurements, and metadata.

## How It Works

The Registry works by walking an application tree and examining every module for Telemetry Event definitions
when invoking the discovery feature.

```erlang
-telemetry_event #{
                   event => [test_app, handler, start],
                   description => <<"Emitted at the start of the handler">>,
                   measurements => <<"#{system_time => non_neg_integer()}">>,
                   metadata => <<"#{}">>
                  }.
-telemetry_event #{
                   event => [test_app, handler, stop],
                   description => <<"Emitted at the end of the handler">>,
                   measurements => <<"#{duration => non_neg_integer()}">>,
                   metadata => <<"#{}">>
                  }.
-telemetry_event #{
                   event => [test_app, handler, exception],
                   description => <<"The handler raised an exception">>,
                   measurements => <<"#{duration => non_neg_integer()}">>,
                   metadata => <<"#{kind => atom(), reason => atom(), stacktrace => term()}">>
                  }.
```

### Add the Registry to Your Application

After the applications are loaded, simply run

```erlang
telemetry_registry:discover_all(my_app).
```

Or if you want to load all applications loaded in current VM then you can use:

```erlang
telemetry_registry:discover_all().
```

### Viewing Events

The defined events can be accessed using `list_events/0`. Events are returned as a list of
three element tuples of `{Event, Module, Meta}` where `Event` is the event name, `Module` is the
module it was discovered in, and Meta is the event definition metadata.

```erlang
telemetry_registry:list_events().
```

### Spannable Events

Tracing spans need at least a matching `start` and `stop` event to create a child span.
Optionally, a `exception` event can be emitted in the case of an exception being raised.
`spannable_events/0` returns a proplist of all matching (spannable) events that have been
discovered. These are returned as a proplist with keys being the event prefix and the value
being a list of the available events, e.g. `[{[test_app,handler], [start,stop,exception]}]`.

```erlang
telemetry_registry:spannable_events().
%% [{[test_app,handler], [start,stop,exception]}]
```

## Elixir Users

A variety of macros to assist with event declaration and generating telemetry event documentation
are available. Please refer to the [HexDocs](https://hex.pm/packages/telemetry_registry) for more
information.

### Dependency in Elixir

``` elixir
def deps do
  [
    {:telemetry_registry, "~> 0.3"}
  ]
end
```

Copyright 2020 Bryan Naegele

TelemetryRegistry source code is released under Apache License, Version 2.0.
