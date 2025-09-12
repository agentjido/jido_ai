# Adding a new provider to **ReqLLM**

_Rev. 2024-06 – compatible with the Anthropic/Gemini v2 architecture_

This guide shows how to write and test a **first-class provider** (e.g. OpenAI, Gemini) for ReqLLM.  

* the `prepare_request/4` callback,
* protocol–based context/response encoding,
* a declarative DSL for registration & option validation,
* first-class error structs (aka *Splode* errors), and
* a Live-Fixture powered test strategy.

Follow the steps below; a checklist is at the end.

---

## 1. Provider module – the new skeleton

```
lib/req_llm/providers/my_provider.ex
```

```elixir
defmodule ReqLLM.Providers.MyProvider do
  @moduledoc "MyProvider – Messages/Chat API."

  @behaviour ReqLLM.Provider           # ❶ mandatory behaviour

  import ReqLLM.Provider.Utils,
    only: [prepare_options!: 3, maybe_put: 3, ensure_parsed_body: 1]

  use ReqLLM.Provider.DSL,            # �② declarative registration
    id: :my_provider,
    base_url: "https://api.my-provider.com/v1",
    metadata: "priv/models_dev/my_provider.json",
    context_wrapper: ReqLLM.Providers.MyProvider.Context,
    response_wrapper: ReqLLM.Providers.MyProvider.Response,
    default_env_key: "MY_PROVIDER_API_KEY",
    provider_schema: [                # ❸ validated request options
      temperature: [type: :float, default: 0.7],
      max_tokens: [type: :pos_integer, default: 1024],
      stream:      [type: :boolean,   default: false],
      system:      [type: :string],
      tools:       [type: {:list, :map}]
    ]

  @doc """
  Build an outbound Req pipeline for the `:chat` operation.
  """
  @impl ReqLLM.Provider
  def prepare_request(:chat, model_input, %ReqLLM.Context{} = ctx, user_opts) do
    with {:ok, model} <- ReqLLM.Model.from(model_input) do
      req =
        Req.new(url: "/messages", method: :post, receive_timeout: 30_000)
        |> attach(model, Keyword.put(user_opts, :context, ctx))

      {:ok, req}
    end
  end

  # Fallback for unsupported operations
  def prepare_request(op, _, _, _),
      do:
        {:error,
         ReqLLM.Error.Invalid.Parameter.exception(
           parameter: "operation #{inspect(op)} not supported"
         )}

  @doc "Low-level Req attachment – installs headers, validation, steps."
  @impl ReqLLM.Provider
  def attach(%Req.Request{} = req, model_input, user_opts \\ []) do
    model = ReqLLM.Model.from!(model_input)
    ensure_correct_provider!(model)

    api_key = fetch_api_key!()

    # -- 1. separate tools before validation
    {tools, other_opts} = Keyword.pop(user_opts, :tools, [])

    # -- 2. validate / coerce options via provider_schema
    opts = prepare_options!(__MODULE__, model, other_opts) |> Keyword.put(:tools, tools)

    # -- 3. install into Req pipeline
    req
    |> Req.Request.register_options(__MODULE__.supported_provider_options() ++ [:model, :context])
    |> Req.Request.merge_options(Keyword.take(opts, [:stream, :model, :context]) ++
                                 [base_url: Keyword.get(user_opts, :base_url, default_base_url())])
    |> Req.Request.put_header("authorization", "Bearer #{api_key}")
    |> ReqLLM.Step.Error.attach()
    |> Req.Request.append_request_steps(llm_encode_body: &encode_body/1)
    |> ReqLLM.Step.Stream.maybe_attach(opts[:stream])
    |> Req.Request.append_response_steps(llm_decode_response: &decode_response/1)
    |> ReqLLM.Step.Usage.attach(model)
  end

  # -- Req step: request encoding --------------------------------------------
  @impl ReqLLM.Provider
  def encode_body(req) do
    body =
      %{
        model:       req.options[:model],
        temperature: req.options[:temperature],
        max_tokens:  req.options[:max_tokens],
        stream:      req.options[:stream]
      }
      |> Map.merge(tools_payload(req.options[:tools]))
      |> Map.merge(context_payload(req.options[:context]))
      |> maybe_put(:system, req.options[:system])

    encoded = Jason.encode!(body)

    req
    |> Req.Request.put_header("content-type", "application/json")
    |> Map.put(:body, encoded)
  end

  # -- Req step: response decoding -------------------------------------------
  @impl ReqLLM.Provider
  def decode_response({req, %{status: 200} = resp}) do
    parsed =
      resp.body
      |> ensure_parsed_body()
      |> ReqLLM.Response.Codec.decode_response(req.options[:model])

    {req, parsed}
  end

  def decode_response({req, resp}) do
    err =
      ReqLLM.Error.API.Response.exception(
        status: resp.status,
        reason: "MyProvider API error",
        response_body: resp.body
      )

    {req, err}
  end

  # -- Usage extraction (optional) -------------------------------------------
  @impl ReqLLM.Provider
  def extract_usage(%{"usage" => u}, _), do: {:ok, u}
  def extract_usage(_, _), do: {:error, :no_usage}

  # -- helpers ---------------------------------------------------------------

  defp tools_payload([]), do: %{}
  defp tools_payload(tools),
    do: %{tools: Enum.map(tools, &ReqLLM.Schema.to_my_provider_format/1)}

  defp context_payload(%ReqLLM.Context{} = ctx),
    do:
      ctx
      |> wrap_context()
      |> ReqLLM.Context.Codec.encode_request()

  defp context_payload(_), do: %{}

  defp ensure_correct_provider!(%ReqLLM.Model{provider: ^provider_id?()}), do: :ok
  defp ensure_correct_provider!(_),
    do: raise ReqLLM.Error.Invalid.Provider.exception(provider: :mismatch)

  defp fetch_api_key! do
    key = JidoKeys.get(default_env_key())
    if key in [nil, ""], do: raise(ReqLLM.Error.Invalid.Parameter,
                                   parameter: "API key '#{default_env_key()}' not set")
    key
  end
end
```

### Key changes vs. the legacy guide

1. **`prepare_request/4`**  
   *Entry-point invoked by high-level helpers (`generate_text/4`, etc.).*  
   Returns `{:ok, %Req.Request{}}` **already wired** with all steps.

2. **Context & Response protocols** (`ReqLLM.Context.Codec`, `ReqLLM.Response.Codec`)  
   Provide **pluggable wire-format translation**.  
   *Context* handles outbound encoding and inbound partial chunk decoding;  
   *Response* turns the final provider JSON (or stream) into a typed
   `ReqLLM.Response` struct.

3. **`use ReqLLM.Provider.DSL`**  
   • Registers the provider under a stable atom (`:my_provider`).  
   • Generates helpers (`provider_id/0`, `default_base_url/0`, …).  
   • Bakes option validation (`provider_schema:`) through NimbleOptions.  
   • Lets you specify custom `context_wrapper` & `response_wrapper` structs.

4. **Splode errors** (`ReqLLM.Error.*`)  
   Never return raw tuples.  
   Raise `ReqLLM.Error.Invalid.Parameter`, `ReqLLM.Error.API.Response`, …  
   The `ReqLLM.Step.Error` pipeline step catches and converts them to `{:error, error}`.

5. **`ReqLLM.Schema`** – tool definitions  
   A single authority to turn NimbleOptions schemas ↔ JSON-Schema.  
   Implement a helper (`to_my_provider_format/1`) if your API's shape diverges.

6. **Streaming**  
   Plug `ReqLLM.Step.Stream.maybe_attach/2`; it installs SSE parsing and dispatches
   chunks through Context-codec logic.  
   The Response codec receives an actual `Stream.t()` when `stream?: true`.

---

## 2. Context & Response codec modules

```
lib/req_llm/providers/my_provider/context.ex
```

```elixir
defmodule ReqLLM.Providers.MyProvider.Context do
  defstruct [:context]
  @type t :: %__MODULE__{context: ReqLLM.Context.t()}
end

# Outbound & inbound translation
defimpl ReqLLM.Context.Codec, for: ReqLLM.Providers.MyProvider.Context do
  # OUTBOUND ---------------------------------------------------------------
  def encode_request(%{context: %ReqLLM.Context{messages: msgs}}) do
    %{messages: Enum.map(msgs, &encode_msg/1)}
  end

  # INBOUND  (chunk list)
  def decode_response(%{"content" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.map(&decode_block/1)
    |> List.flatten()
  end

  # helpers ...
end
```

```
lib/req_llm/providers/my_provider/response.ex
```

```elixir
defmodule ReqLLM.Providers.MyProvider.Response do
  defstruct [:payload]
  @type t :: %__MODULE__{payload: term()}
end

defimpl ReqLLM.Response.Codec, for: ReqLLM.Providers.MyProvider.Response do
  alias ReqLLM.{Response, Context}

  # Final non-streaming
  def decode_response(%{payload: data}, model) when is_map(data) do
    with {:ok, chunks} <- ReqLLM.Context.Codec.decode_response(data),
         message       <- build_message(chunks) do
      resp = %Response{
        id: Map.get(data, "id"),
        model: Map.get(data, "model", model.model),
        context: %Context{messages: [message]},
        message: message,
        stream?: false,
        usage: Map.get(data, "usage", %{}),
        finish_reason: Map.get(data, "finish_reason")
      }

      {:ok, resp}
    end
  end

  # Streaming variant receives a Stream.t()
  def decode_response(%{payload: %Stream{} = stream}, model) do
    {:ok,
     %Response{
       id: "stream",
       model: model.model,
       context: %Context{messages: []},
       stream?: true,
       stream: stream,
       usage: %{}
     }}
  end
end
```

Start with **text only**; add images, tool calls, thinking tokens later.

---

## 3. Capability metadata

`priv/models_dev/my_provider.json`

```jsonc
{
  "provider": {
    "env": ["MY_PROVIDER_API_KEY"]
  },
  "models": [
    {
      "id": "small-1",
      "max_tokens": 8192,
      "streaming": true,
      "tool_call": true,
      "temperature": true,
      "top_p": true
    }
  ]
}
```

New flags → add mapping in `ReqLLM.Capability.from_json/1`.

---

## 4. Testing with **LiveFixture**

```
test/coverage/my_provider/core_test.exs
```

```elixir
defmodule ReqLLM.Coverage.MyProvider.CoreTest do
  use ExUnit.Case, async: false
  @moduletag :coverage
  @moduletag :my_provider

  alias ReqLLM.Test.LiveFixture
  @model "my_provider:small-1"

  test "simple completion" do
    result =
      LiveFixture.use_fixture(:my_provider, "simple_completion", fn ->
        ctx = ReqLLM.Context.new([ReqLLM.Context.user("ping?")])
        ReqLLM.generate_text(@model, ctx, max_tokens: 3, temperature: 0)
      end)

    {:ok, resp} = result
    assert resp.message.content |> Enum.at(0) |> Map.get(:text) =~ "pong"
  end
end
```

Run:

```
mix test --exclude coverage          # unit only
mix test --only coverage             # fixture layer (offline)
LIVE=true mix test --only coverage   # re-record fixtures (paid API)
```

---

## 5. Best practices

1. Keep `prepare_request/4` tiny – put heavy logic in private helpers.  
2. **No global state**; the provider struct merely wraps `ReqLLM.Context`.  
3. All added fields in `encode_request/1` **must** be reversed in `decode_response/1`.  
4. Raise `ReqLLM.Error.*` from helpers; never leak `{:error, term}` tuples.  
5. Guard against missing API keys with `fetch_api_key!`.  
6. Use the cheapest model for fixtures; deterministic prompts (`temperature: 0`).  
7. Document quirks in `@moduledoc`.

---

## 6. Developer checklist

- [ ] `lib/req_llm/providers/<provider>.ex` with behaviour + DSL + prepare_request/4  
- [ ] `lib/req_llm/providers/<provider>/context.ex` implementing `ReqLLM.Context.Codec`  
- [ ] `lib/req_llm/providers/<provider>/response.ex` implementing `ReqLLM.Response.Codec`  
- [ ] `priv/models_dev/<provider>.json` capability map  
- [ ] Unit tests for encode/decode helpers  
- [ ] Coverage tests + fixtures under `test/coverage/<provider>/`  
- [ ] Run `LIVE=true mix test --only coverage --only <provider>` for first recording  
- [ ] CI must pass unit + fixture layers  

Welcome to the ReqLLM ecosystem – happy hacking!  
