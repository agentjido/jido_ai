# Private—Expose private functions for testing.

Sometimes you want to test all those private functions in your
modules. But Elixir doesn't make it easy to get to them. As a
result, you end up trying to exercise them by setting up convoluted
calls to the public API.

`private` to the rescue. It switches the visibility of functions so
that they are exposed when the Mix environment is `:test`, and
private otherwise.

      defmodule MyMod do
        use Private

        def api1() do ...
        def api2() do ...

        private do
          def helper1() do...
          def helper2() do...
        end

        def api3() do ...

        private do
          defp helper3() do...
        end
     end


All functions in the `private` block will be defined as private
unless the Mix environment is `:test`. 

In the test environment, `def` will be left unchanged, and `defp` will
be changed to `def`. In all other environments, `def` will be changed
to `defp` and `defp` will be left unchanged.


## Installation

```elixir
@deps [
  { private: "> 0.0.0" ],
]
```

