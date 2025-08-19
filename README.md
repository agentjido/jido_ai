# Sparq

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `sparq` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sparq, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/sparq>.

Potential Optimizations
Partial Compilation: For performance-critical scripting, you could partially compile the AST to real Elixir code, then load it on-the-fly. This is akin to how Elixir macros do code generation. It’s definitely more complex, but drastically faster in tight loops.

Inline Built-ins: For things like arithmetic (:add), you might consider inlining or direct pattern matching in your interpreter, skipping an apply call to Sparq.Handlers.Math.handle/4. If you do want a truly pluggable language, that might be less of a concern.

Tail Recursion: If you often have lists of commands that produce no intermediate result, you might rewrite your Enum.reduce as a tail-recursive function. The BEAM’s optimization for tail calls can help if the script is large. This is more of an incremental improvement, though.

Recommendations Going Forward
Keep It Simple (Initially)
You have a neat design for an embedded DSL or lightweight scripting language. Don’t over-optimize prematurely. The Beam can handle quite a bit with your interpretive approach.

Consider an Optional “Compiler Pass”
If scripts get large or performance-sensitive, you can add an optional pass that translates your AST into either pure Elixir code or a “lowered” form that’s faster to run. Something like:

elixir
Copy code
# Potential pseudo-compiler
def compile({:add, meta, [a, b]}) do
  quote do
    unquote(compile(a)) + unquote(compile(b))
  end
end
Then Code.eval_quoted/2 or even “real” module compilation. That’s advanced but extremely powerful.

Refine Scoping
If you decide you need real lexical scoping or nested function definitions that capture variables, you’ll want a layered environment approach. For instance, push a new %{vars: ...} map on entry to a function, pop it on exit. Or store them in a stack-like structure.

Keep “Handlers” for Builtins
This pluggable model is excellent. Consider allowing user scripts to register new handlers. That’s a great extension point for building user-defined library modules in pure script code.

Track Line Numbers
For robust error messages, you might eventually want more thorough usage of the meta argument. Store line and file (and possibly column) across all nodes so you can say: “Error at line 42: cannot call nil function,” etc.