# Kday
![Build status](https://github.com/kipcole9/kday/actions/workflows/ci.yml/badge.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/kday.svg)](https://hex.pm/packages/kday)
[![Hex.pm](https://img.shields.io/hexpm/dw/kday.svg?)](https://hex.pm/packages/kday)
[![Hex.pm](https://img.shields.io/hexpm/dt/kday.svg?)](https://hex.pm/packages/kday)
[![Hex.pm](https://img.shields.io/hexpm/l/kday.svg)](https://hex.pm/packages/kday)

## Introduction

`kday` provides functions to return the date of the first, last or nth day of the week on, nearest, before or after a given date.

## Kday Installation

Add `kday` to your `deps` in `mix.exs`.

```elixir
def deps do
  [
    {:kday, "~> 1.0"}
    ...
  ]
end
```

## Functions

* [first_kday(date, k)](https://hexdocs.pm/kday/Kday.html#first_kday/2) - Return the date of the first `day_of_week` on or after the specified `date`.

* [kday_after(date, k)](https://hexdocs.pm/kday/Kday.html#kday_after/2) - Return the date of the `day_of_week` after the specified `date`.

* [kday_before(date, k)](https://hexdocs.pm/kday/Kday.html#kday_before/2) - Return the date of the `day_of_week` before the specified `date`.

* [kday_nearest(date, k)](https://hexdocs.pm/kday/Kday.html#kday_nearest/2) - Return the date of the `day_of_week` nearest the specified `date`.

* [kday_on_or_after(date, k)](https://hexdocs.pm/kday/Kday.html#kday_on_or_after/2) - Return the date of the `day_of_week` on or after the specified `date`.

* [kday_on_or_before(date, k)](https://hexdocs.pm/kday/Kday.html#kday_on_or_before/2) - Return the date of the `day_of_week` on or before the specified `date`.

* [last_kday(date, k)](https://hexdocs.pm/kday/Kday.html#last_kday/2) - Return the date of the last `day_of_week` on or before the specified `date`.

* [nth_kday(date, n, k)](https://hexdocs.pm/kday/Kday.html#nth_kday/3) - Return the date of the `nth` `day_of_week` on or before/after the specified `date`.

## Examples
Days of the week follow the elixir convention of `1` being Monday and `7` being Sunday.

```elixir
# Memorial Day in the US
iex> Kday.last_kday(~D[2017-05-31], 1)
~D[2017-05-29]

iex> Kday.kday_nearest(~D[2016-02-29], 2)
~D[2016-03-01]

iex> Kday.kday_on_or_after(~D[2017-11-30], 1)
~D[2017-12-04]
```


