# Backoff

Backoff is an Erlang library to deal with exponential backoffs and timers to
be used within OTP processes when dealing with cyclical events, such as
reconnections, or generally retrying things.

# Compiling

    rebar3 compile

# Running Tests

Tests are implemented as a basic PropEr property-based test suite. Running them
requires getting PropEr for the project. The following command line does
everything needed:

    $ rebar3 as test proper

# Modes of Operation

Backoff can be used in 3 main ways:

1. a simple way to calculate exponential backoffs
2. calculating exponential backoffs with caps and state tracking
3. using it to fire timeout events

## Simple Backoffs

Simple backoffs work by calling the functions `increment/1-2`. The function
with one argument will grow in an unbounded manner:

    1> backoff:increment(1).
    2
    2> backoff:increment(backoff:increment(1)).
    4
    3> backoff:increment(backoff:increment(backoff:increment(1))).
    8

The version with 2 arguments specifies a ceiling to the value:

    4> backoff:increment(backoff:increment(backoff:increment(2))).
    16
    5> backoff:increment(backoff:increment(backoff:increment(2)), 10).
    10

## Simple Backoffs with jitter

Jitter based incremental backoffs increase the back off period for each retry attempt using a randomization function that grows exponentially. They work by calling the functions `rand_increment/1-2`. The function with one argument will grow in an unbounded manner:

    1> backoff:rand_increment(1).
    3
    2> backoff:rand_increment(backoff:rand_increment(1)).
    7
    3> backoff:rand_increment(backoff:rand_increment(backoff:rand_increment(1))).
    19
    4> backoff:rand_increment(backoff:rand_increment(backoff:rand_increment(1))).
    14
    5> backoff:rand_increment(backoff:rand_increment(backoff:rand_increment(1))).
    17

The version with 2 arguments specifies a ceiling to the value. If the
delay is close to the ceiling the new delay will also be close to the
ceiling and may be less than the previous delay.

    6> backoff:rand_increment(backoff:rand_increment(backoff:rand_increment(2))).
    21
    7> backoff:rand_increment(backoff:rand_increment(backoff:rand_increment(2)), 10).
    10

## State Backoffs

State backoffs keep track of the current value, the initial value, and the
maximal value for you. A backoff of that kind is initialized by calling
`init(Start,Max)` and returns an opaque data type to be used with `get/1`
(fetches the current timer value), `fail/1` (increments the value), and
`succeed/1` (resets the value):

    6> B0 = backoff:init(2, 10).
    ...
    7> {_, B1} = backoff:fail(B0).
    {4, ...}
    8> backoff:get(B1).
    4
    9> {_, B2} = backoff:fail(B1).
    {8, ...}
    10> {_, B3} = backoff:fail(B2).
    {10, ...}
    11> {_, _} = backoff:fail(B3).
    {10, ...}

And here we've hit the cap with the failures. Now to succeed again:

    12> {_, B4} = backoff:succeed(B3).
    {2, ...}
    13> backoff:get(B4).
    2

That way, backoffs carry all their relevant state.

If what you want are unbound exponential backoffs, you can initiate them with:

    14> backoff:init(Start, 'infinity').

And still use them as usual. The increments will have no upper limit.

## State Backoffs with jitter

You can enable a jitter based incremental backoff by calling `type/2`
that swaps the state of the backoff:

    1> B0 = backoff:init(2, 30).
    {backoff,2,30,2,normal,undefined,undefined}
    2> B1 = backoff:type(B0, jitter).
    {backoff,2,30,2,jitter,undefined,undefined}
    3> {_, B2} = backoff:fail(B1).
    {7, ...}
    4> {_, B3} = backoff:fail(B2).
    {12, ...}

Calling `type/2` with argument `normal` will swap the backoff state back
to its default behavior:

    5> B4 = backoff:type(B3, normal).
    {backoff,2,30,12,normal,undefined,undefined}
    6> {_, B5} = backoff:fail(B4).
    {24, ...}

## Timeout Events

A very common usage for exponential backoffs are with timer events, to be used
when driving reconnections or retries to certain sources. Most implementations
of this will call `erlang:start_timer(Delay, Dest, Message)` to do this, and
re-use the same values all the time.

Given we want Backoff to carry us the whole way there, additional arguments can
be given to the `init` function to deal with such state and fire events
whenever necessary. We first initialize the backoff with `init(Start, Max,
Dest, Message)`:

    1> B = backoff:init(5000, 20000, self(), hello_world).
    ...

Then by entering:

    2> backoff:fire(B). timer:sleep(2500), flush(). timer:sleep(3000), flush().

and pressing enter, the following sequence of events will unfold:

    3> backoff:fire(B). timer:sleep(2500), flush(). timer:sleep(3000), flush().
    #Ref<0.0.0.719>
    4> timer:sleep(2500), flush(). timer:sleep(3000), flush().
    ok
    5> timer:sleep(3000), flush().
    Shell got {timeout,#Ref<0.0.0.719>,hello_world}
    ok

Showing that `backoff:fire/1` generates a new timer, and returns the timer
reference. This reference can be manipulated with `erlang:cancel_timer(Ref)`
and `erlang:read_timer(Ref)`.

The shell then sleeps (2000 ms), receives nothing, then sleeps some more (3000
ms) and finally receives the timeout event as a regular Erlang timeout message.

Do note that Backoff will *not* track the timer references given there can be
enough use cases with multiple timers, event cancellation, and plenty of other
things that can happen with them. Backoff makes it easy to fire them for
the right interval, but *it is not* a wrapper around Erlang timers for all
operations.

# Changelog

- 1.1.6: fix compile regexes since darwin version 17.5 would be confused with OTP 17.x
- 1.1.5: move `proper` plugin to test profile to avoid build warnings on newer Erlangs
- 1.1.4: fix dialyzer warnings, update doc
- 1.1.3: switch to package version of PropEr plugin to avoid mix conflicts
- 1.1.2: eliminate compilation warnings
- 1.1.1: corrections to incremental backoff
- 1.1.0: added jitter based incremental backoff
- 1.0.0: initial commit stable for over a year
