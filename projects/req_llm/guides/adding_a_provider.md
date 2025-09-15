# Adding a new provider to **ReqLLM**

_Rev. 2025-01 – ReqLLM 1.0.0-rc.1_

## Developer checklist

- [ ] `lib/req_llm/providers/<provider>.ex` with behaviour + DSL + prepare_request/4  
- [ ] `lib/req_llm/providers/<provider>/context.ex` implementing `ReqLLM.Context.Codec`  
- [ ] `lib/req_llm/providers/<provider>/response.ex` implementing `ReqLLM.Response.Codec`  
- [ ] `priv/models_dev/<provider>.json` capability metadata  
- [ ] Unit tests for encode/decode helpers  
- [ ] Coverage tests + fixtures under `test/coverage/<provider>/`  
- [ ] Run `LIVE=true mix test --only coverage --only <provider>` for first recording  
- [ ] CI must pass unit + fixture layers  

## Overview

This guide shows how to write a **first-class provider** for ReqLLM using:

* The `prepare_request/4` callback
* Protocol-based context/response encoding
* Declarative DSL for registration & option validation
* Structured error handling with Splode errors
* Capability-based testing with LiveFixture

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
    # Provider-specific options only - core options handled centrally
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
  def attach(%Req.Request{} = request, model_input, user_opts \\ []) do
    %ReqLLM.Model{} = model = ReqLLM.Model.from!(model_input)

    # Validate provider match
    unless model.provider == provider_id() do
      raise ReqLLM.Error.Invalid.Provider.exception(provider: model.provider)
    end

    # Validate model exists in registry
    unless ReqLLM.Provider.Registry.model_exists?("#{provider_id()}:#{model.model}") do
      raise ReqLLM.Error.Invalid.Parameter.exception(parameter: "model: #{model.model}")
    end

    # Get API key from JidoKeys
    api_key_env = ReqLLM.Provider.Registry.get_env_key(provider_id())
    api_key = JidoKeys.get(api_key_env)

    unless api_key && api_key != "" do
      raise ReqLLM.Error.Invalid.Parameter.exception(
              parameter: "api_key (set via JidoKeys.put(#{inspect(api_key_env)}, key))"
            )
    end

    # Extract tools separately to avoid validation issues
    {tools, other_opts} = Keyword.pop(user_opts, :tools, [])

    # Prepare validated options
    opts = prepare_options!(__MODULE__, model, other_opts)
    opts = Keyword.put(opts, :tools, tools)
    base_url = Keyword.get(user_opts, :base_url, default_base_url())
    req_keys = __MODULE__.supported_provider_options() ++ [:model, :context]

    # Build Req pipeline
    request
    |> Req.Request.register_options(req_keys)
    |> Req.Request.merge_options(Keyword.take(opts, req_keys) ++ [base_url: base_url])
    |> Req.Request.put_header("authorization", "Bearer #{api_key}")
    |> ReqLLM.Step.Error.attach()
    |> Req.Request.append_request_steps(llm_encode_body: &__MODULE__.encode_body/1)
    |> ReqLLM.Step.Stream.maybe_attach(opts[:stream])
    |> Req.Request.append_response_steps(llm_decode_response: &__MODULE__.decode_response/1)
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
  def decode_response({req, resp}) do
    case resp.status do
      200 ->
        body = ensure_parsed_body(resp.body)
        # Return raw parsed data directly - no wrapping needed
        {req, %{resp | body: body}}

      status ->
        err =
          ReqLLM.Error.API.Response.exception(
            reason: "MyProvider API error",
            status: status,
            response_body: resp.body
          )

        {req, err}
    end
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


end
```

### Key changes in ReqLLM 1.0.0-rc.1

1. **Provider validation**  
   Use `model.provider == provider_id()` instead of `ensure_correct_provider!()`.
   DSL generates `provider_id/0` helper automatically.

2. **Model registry**  
   Validate models via `ReqLLM.Provider.Registry.model_exists?/1`.

3. **API key handling**  
   Use `JidoKeys.get/1` with registry-provided env key. Keys are automatically loaded from .env via JidoKeys+Dotenvy integration, or can be set directly via `ReqLLM.put_key/2`.

4. **Core options centralized**  
   `provider_schema` now only for provider-specific options.
   Temperature, max_tokens, system, stream handled centrally.

5. **Response decoding simplified**  
   Return `{req, %{resp | body: parsed_body}}` directly - no wrapper struct needed.

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

New flags → add mapping in the provider's capability metadata.

---

## 4. Capability testing

Create provider-specific tests under `test/coverage/<provider>/`. 
See [capability-testing.md](capability-testing.md) for comprehensive testing guide.

Basic structure:

```
test/coverage/my_provider/
├── core_test.exs         # Text generation
├── streaming_test.exs    # Streaming responses  
└── tool_calling_test.exs # Function calling
```

Example:

```elixir
defmodule ReqLLM.Coverage.MyProvider.CoreTest do
  use ExUnit.Case, async: false
  @moduletag :coverage
  @moduletag :my_provider

  alias ReqLLM.Test.LiveFixture
  @model "my_provider:small-1"

  test "basic completion" do
    {:ok, resp} =
      LiveFixture.use_fixture(:my_provider, "basic_completion", fn ->
        ReqLLM.generate_text(@model, "Hello!", max_tokens: 10, temperature: 0)
      end)

    assert is_binary(resp.message.content)
  end
end
```

Commands:

```bash
mix test --only my_provider                    # Provider tests only
LIVE=true mix test --only my_provider          # Record fixtures
FIXTURE_FILTER=my_provider mix test            # Regenerate specific provider
```

---

## 5. Best practices

* Keep `prepare_request/4` minimal - delegate to `attach/3`
* Use `provider_id()` helper for validation, not hardcoded atoms
* Provider schema only for provider-specific options 
* Use `JidoKeys` for API key management - keys are automatically loaded from .env files
* Return raw parsed response body from `decode_response/1`
* Test with cheapest model using `temperature: 0` for deterministic fixtures
* Start with text-only support, add multimodal features incrementally

---

Welcome to ReqLLM 1.0!  
