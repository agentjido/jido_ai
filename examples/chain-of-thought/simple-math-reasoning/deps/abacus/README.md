# Abacus ![Build status](https://travis-ci.org/narrowtux/abacus.svg)

A simple and safe script language for the BEAM.

https://hex.pm/packages/abacus

## Language

This language was written to be so simple anyone that has seen mathematical terms before can write Abacus code.

For example, adding `a` and `b` is as simple as `a + b`.

It was also designed to be as safe as possible, allowing you to expose the compiler to a web frontend.

### Simplicity

A lot of features make this language easier to use and less confusing than regular Elixir (to laymen) with a [whitelist](https://github.com/ZennerIoT/loppers):

 * All common math operators are available as binary operators
 * No string/atom confusion when 
   * accessing maps or keyword lists
   * comparing 2 variables
 * Since it is using the Elixir AST, a lot of the advantages apply:
   * Functional
   * Immutable
   * Everything is an expression (even if statements)
   * Last expression returns
 
### Safety

Several measures have been or can be taken to allow *safe execution* of *untrusted code*.

 * Scripts don't have access to Erlang/Elixir modules and their functions
 * For variables, atoms are reused across different scripts
   * Variables will be renamed into `:var0`, `var1`, ..., `varn` where n is the amount of distinct variable names in a script
   * Variable amounts can be limited so bad actors can't DoS your service by creating scripts with more variables than the VM atom limit
 * You can move execution off to a dedicated process to 
   * Prevent endless loops (set a timeout)
   * Prevent heavy memory usage (set `max_heap_size: %{size: 1_000_000, kill: true}` in process options)
 * If you use a worker pool you can even prevent DoS attacks that spawn thousands of parallel executions in the allowed timeout (note: phoenix already uses a worker pool so you don't have to spawn your own if you execute abacus expression as a response to a HTTP call)

### Performance

While one-off executions can be evaluated using interpretation (through `Code.eval_quoted`), the real power comes from the Abacus parser returning valid Elixir AST. 

This means that the AST can be compiled to BEAM bytecode for performant execution. The performance should be the same as normal Elixir code.

### Use cases
 
 * Write complex filters
 * As a language for map/reduce operations of all kinds
 * For user-supplied export scripts
 * Language for rule-engines (if this then that, authorization rules)

## Usage

`Abacus.eval(expression, scope)`

Parses and evaluates the given expression. Variables can be supplied as a map of
binaries in the `scope`.

#### Examples

```elixir
iex> Abacus.eval("1 + 1")
{:ok, 2}
iex> Abacus.eval("sin(floor(3 + 2.5)) / 3")
{:ok, -0.3196414248877128}
iex> Abacus.eval("a * b", %{"a" => 10, "b" => 10})
{:ok, 100}
```

`Abacus.parse(expression)`

Parses the expression and returns the syntax tree.

The syntax tree is in quoted elixir. This means that you can use this to compile it into BEAM bytecode for performant execution. 

### Language features

An incomplete list of supported and planned features

 - [x] basic operators (`+`, `-`, `*`, `/`, `^`)
 - [x] factorial (`!`)
 - [x] bitwise operators (`|`, `&`, `>>`, `<<`, `~`, `|^` (xor))
 - [x] boolean operators (`&&`, `||`, `not`)
 - [x] comparison operators (`==`, `!=`, `>`, `<`, `>=`, `<=`)
 - [x] grouping terms with parantheses
 - [x] ternary if operator (`condition ? if_true : if_false`)
 - [x] different data types:
   - [x] integers
   - [x] floats
   - [x] strings
   - [x] boolean (`true` and `false`)
   - [x] nulls (`nil`)
 - [x] support for functions
   - [x] trigonometric functions(`sin`, `cos`, `tan`)
   - [x] floating point manipulation(`ceil`, `floor`, `round`)
 - [ ] lambdas (`(x, y) => {x + y}`)
 - [ ] do blocks (`{statement \n statement}`)
 - [ ] variable assignments
 - [ ] enumerable API (`map`, `reduce`, `filter`, ...)
 - [-] literals
   - [x] integers
   - [x] floats
   - [x] strings
   - [ ] lists
   - [ ] maps
 - [x] support for variables

## Installation

1. Add `abacus` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:abacus, "~> 0.4.2"}]
  end
  ```

2. Ensure `abacus` is started before your application:

  ```elixir
  def application do
    [applications: [:abacus]]
  end
  ```
