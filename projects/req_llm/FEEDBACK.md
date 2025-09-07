# ReqLLM – Focused Implementation Feedback  
**Reviewer:** Amp Oracle  
**Date:** September 6 2025  

This revision keeps the existing module layout intact and zooms in on concrete, code-level improvements the team has approved.

---

## 1. Elixir Idioms & Conventions

### 1.1 Use Multiple Function Clauses
Replace guard-heavy functions with clear clause heads.

```elixir
# Before
def valid?(%__MODULE__{role: role, content: content}) when role in [...]

# After
def valid?(%__MODULE__{role: :tool, tool_call_id: nil}), do: false
def valid?(%__MODULE__{role: :tool} = m),               do: content_valid?(m.content)
def valid?(%__MODULE__{} = m),                          do: content_valid?(m.content)
def valid?(_),                                          do: false
```

Benefits: pattern-matching communicates intent, removes internal `case`, and the compiler can warn about unhandled patterns.

### 1.2 Prefer Atoms for Enum-Like Fields
`ObjectSchema.enum_values` now returns strings. Convert to atoms at schema-creation time:

```elixir
# object_schema.ex
def new(opts) when is_list(opts) do
  enum_atoms = Keyword.get(opts, :enum_values, []) |> Enum.map(&String.to_atom/1)
  ...
end
```

This eliminates `String.to_existing_atom/1` rescue blocks and lets the compiler validate enum usage.

### 1.3 Avoid `try/rescue` for Expected Flow
`compile_schema/1` rescues to wrap invalid schemas. Swap to non-bang API and explicit pattern matching:

```elixir
defp compile_schema(props) do
  case NimbleOptions.new(props) do
    {:ok, schema} -> {:ok, schema}
    {:error, err} -> {:error, validation_error(:invalid_schema, Exception.message(err))}
  end
end
```

### 1.4 Pattern-Match Early on Inputs
Unify APIs like `api_key/1`:

```elixir
def api_key(key) when is_atom(key),  do: key |> Atom.to_string() |> api_key()
def api_key(key) when is_binary(key) do
  Kagi.get(String.downcase(key))
end
```

### 1.5 Enforce Required Keys at Compile Time
Add `@enforce_keys` to structs such as `Provider`, `Message`, and `ObjectSchema` so missing keys crash fast:

```elixir
typedstruct enforce: true do
  field :role, role()
  field :content, String.t() | [ContentPart.t()]
end
```

---

## 2. Build Option Schemas Programmatically

The two NimbleOptions schemas in `req_llm.ex` share ~90 % of fields.

```elixir
# req_llm.ex
@base_gen_opts [
  temperature:        [type: :float, doc: "..."],
  max_tokens:         [type: :pos_integer, doc: "..."],
  ...
]

@text_opts_schema   NimbleOptions.new!(@base_gen_opts)
@object_opts_schema NimbleOptions.new!(
                      @base_gen_opts ++ [
                        output_type:  [type: {:in, [:object, :array, :enum, :no_schema]}, default: :object],
                        enum_values:  [type: {:list, :string}]
                      ]
                    )
```

Benefits: one source of truth, simpler option evolution, smaller diff noise.

---

## 3. Splode Error Module Cleanup

Problem: 16+ bespoke error structs slow compilation and obscure the public surface.

Action plan (without abandoning Splode):

1. Keep three public error structs  
   • `ReqLLM.Error.Invalid` (input / config)  
   • `ReqLLM.Error.API`      (HTTP and provider faults)  
   • `ReqLLM.Error.Validation` (schema & result validation)  

2. All other Splode modules become private helpers or folded into the three above via `:class` tags.

Example:

```elixir
# Replace many tiny modules with tagged variants
defmodule ReqLLM.Error.API do
  use Splode.Error, class: :api, fields: [:tag, :reason, :status, :data]

  def message(%{tag: :request, status: s, reason: r}),   do: "HTTP #{s}: #{r}"
  def message(%{tag: :response, status: s, reason: r}),  do: "Bad response #{s}: #{r}"
  def message(%{reason: r}),                             do: "API error: #{r}"
end
```

3. Update callers gradually:

```elixir
{:error, ReqLLM.Error.API.exception(tag: :request, status: 500, reason: "Timeout")}
```

Outcome: same Splode semantics, faster compile times, simpler error matching.

---

## 4. API Design Improvements

### 4.1 Accept Plain Strings & IOLists
Add `iodata?` checks so callers can pass IO lists without manual `IO.iodata_to_binary/1`.

```elixir
def generate_text(model, prompt, opts \\ [])
def generate_text(model, prompt, opts) when is_binary(prompt),
  do: do_generate(model, prompt, opts)
def generate_text(model, prompt, opts) when is_list(prompt),
  do: do_generate(model, IO.iodata_to_binary(prompt), opts)
```

### 4.2 Model Spec Coercion
Centralise parsing in `ReqLLM.Model.new/1`:

```elixir
def new("openai:" <> rest), do: parse_string(:openai, rest, [])
def new({provider, kw}) when is_atom(provider) and is_list(kw), do: struct(__MODULE__, kw ++ [provider: provider])
```

Implement `String.Chars`:

```elixir
defimpl String.Chars, for: ReqLLM.Model do
  def to_string(%{provider: p, model: m}), do: "#{p}:#{m}"
end
```

### 4.3 Streaming Improvements
Expose a finite `Stream` instead of raw SSE:

```elixir
def stream_text(model, msgs, opts \\ []) do
  Stream.resource(fn -> start_conn(...) end,
                  &next_chunk/1,
                  &Req.close/1)
end
```

Now callers can `Enum.to_list/1` or pipe into `Stream.transform/3`.

### 4.4 Provider Options Consistency
Single source of truth: top-level `opts`.

Internally merge per-message metadata:

```elixir
merged_opts =
  messages
  |> Enum.flat_map(&ReqLLM.Message.provider_options/1)
  |> Enum.into(opts[:provider_options] || %{})
```

Providers then read only from `opts.provider_options`.

---

## 5. Replace Nested `case` with `with`

Identify deep `case` nests (e.g. `parse_tool_response/2`, `build_validating_stream/4`) and linearise them:

```elixir
with  %{tool_calls: calls} <- resp.body,
      %{arguments: args} <- Enum.find(calls, & &1.name == "response_object"),
      {:ok, validated}   <- NimbleOptions.validate(args, schema) do
  {:ok, validated}
else
  nil             -> {:error, error(:tool_not_found)}
  {:error, reason} -> {:error, reason}
end
```

Advantages:  
• Straight-line happy path  
• Early bail-out on failure  
• Readable diff for future changes

---

### Next Steps Checklist
- [ ] Refactor functions listed in 1.1 and 5 to use clauses/`with`.
- [ ] Convert enum strings to atoms and delete rescue logic.
- [ ] Replace `try/rescue` in schema compilation.
- [ ] Add `@enforce_keys` where fields are mandatory.
- [ ] Introduce `@base_gen_opts`, regenerate schemas.
- [ ] Consolidate Splode error modules into three public structs.
- [ ] Implement IO list support in generation APIs.
- [ ] Add `ReqLLM.Model.new/1` and protocol implementations.
- [ ] Return finite `Stream` from `stream_text/3` and `stream_object/4`.
- [ ] Merge message-level provider options into top-level opts.

Implementing these targeted changes will make ReqLLM more idiomatic, performant, and ergonomic while preserving the current architecture.
