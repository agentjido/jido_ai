# ReAct benchmarks

These offline benchmarks measure state growth and live BEAM memory during a
deterministic ReAct workflow. The scripted model requests one small `echo` tool
call per round and then returns `done`. No provider key or network connection is
required.

## State growth

Run the default 5-round and 20-round probes:

```sh
mix bench.react
```

Pass one or more round counts to select shorter probes:

```sh
mix bench.react 5
mix bench.react 5 10 20
```

The report shows model calls, completed tool rounds, fact counts, canonical
item counts, external term sizes, and elapsed time. Fact tracing copies values
to a collector, so use the memory benchmark for live-memory measurements.

## Live memory

Run the default 20-round VM memory probe:

```sh
mix bench.react.memory
```

Pass one round count to select another run length:

```sh
mix bench.react.memory 8
```

The report samples `:erlang.memory/0` every 25 milliseconds. It prints baseline,
peak, increase, and final values for total, process, binary, and ETS memory. It
also prints the largest processes at the total-memory peak.

## Design

The benchmark uses the main project's test dependencies. It does not have its
own Mix project, lock file, dependency checkout, Mix task, or environment
variable interface. The benchmark interface permits up to 20 tool rounds, but
each model round and Action comes from the production ReAct implementation.
