defmodule Jido.AI.Models do
  @moduledoc false
  alias Jido.AI.ModelAliases
  alias ReqLLM.Context

  @type model_alias ::
          :fast | :capable | :thinking | :reasoning | :planning | :image | :embedding | atom()
  @type model_spec :: String.t()
  @type model_input :: model_alias() | ReqLLM.model_input()
  @type llm_kind :: :text | :object | :stream
  @type llm_generation_opts :: %{
          optional(:model) => model_input(),
          optional(:system_prompt) => String.t(),
          optional(:max_tokens) => non_neg_integer(),
          optional(:temperature) => number(),
          optional(:timeout) => pos_integer()
        }

  @default_llm_defaults %{
    text: %{
      model: :fast,
      temperature: 0.2,
      max_tokens: 1024,
      timeout: 30_000
    },
    object: %{
      model: :thinking,
      temperature: 0.0,
      max_tokens: 1024,
      timeout: 30_000
    },
    stream: %{
      model: :fast,
      temperature: 0.2,
      max_tokens: 1024,
      timeout: 30_000
    }
  }

  @doc """
  Returns all configured model aliases merged with defaults.

  User overrides from `config :jido_ai, :model_aliases` are merged on top of built-in defaults.

  ## Examples

      iex> aliases = Jido.AI.model_aliases()
      iex> is_binary(aliases[:fast])
      true
  """
  @spec model_aliases() :: %{model_alias() => ReqLLM.model_input()}
  def model_aliases, do: ModelAliases.model_aliases()

  @doc """
  Returns configured LLM generation defaults merged with built-in defaults.

  Configure under `config :jido_ai, :llm_defaults`.
  """
  @spec llm_defaults() :: %{llm_kind() => llm_generation_opts()}
  def llm_defaults do
    configured = Application.get_env(:jido_ai, :llm_defaults, %{})

    Map.merge(@default_llm_defaults, configured, fn _kind, default_opts, configured_opts ->
      if is_map(configured_opts) do
        Map.merge(default_opts, configured_opts)
      else
        default_opts
      end
    end)
  end

  @doc """
  Returns defaults for a specific generation kind: `:text`, `:object`, or `:stream`.
  """
  @spec llm_defaults(llm_kind()) :: llm_generation_opts()
  def llm_defaults(kind) when kind in [:text, :object, :stream] do
    Map.fetch!(llm_defaults(), kind)
  end

  def llm_defaults(kind) do
    raise ArgumentError,
          "Unknown LLM defaults kind: #{inspect(kind)}. " <>
            "Expected one of: :text, :object, :stream"
  end

  @doc """
  Resolves a model alias or passes through a direct ReqLLM model input.

  Model aliases are atoms like `:fast`, `:capable`, `:reasoning` that map
  to full ReqLLM model specifications. Both alias values and direct model
  inputs may be strings, ReqLLM tuples, inline maps, or `%LLMDB.Model{}`
  structs.

  ## Arguments

    * `model` - Either a model alias atom or a direct ReqLLM model input

  ## Returns

    A resolved ReqLLM model input.

  ## Examples

      iex> String.contains?(Jido.AI.resolve_model(:fast), ":")
      true

      iex> Jido.AI.resolve_model("openai:gpt-4")
      "openai:gpt-4"

      iex> Jido.AI.resolve_model({:openai, "gpt-4.1", []})
      {:openai, "gpt-4.1", []}

      Jido.AI.resolve_model(:unknown_alias)
      # raises ArgumentError with unknown alias message
  """
  @spec resolve_model(model_input()) :: ReqLLM.model_input()
  def resolve_model(model) when is_atom(model), do: ModelAliases.resolve_model(model)
  def resolve_model(model) when is_binary(model), do: model
  def resolve_model(%LLMDB.Model{} = model), do: model
  def resolve_model(model) when is_map(model) and not is_struct(model), do: model

  def resolve_model({provider, model_id, provider_opts} = model)
      when is_atom(provider) and is_binary(model_id) and is_list(provider_opts),
      do: model

  def resolve_model({provider, provider_opts} = model)
      when is_atom(provider) and is_list(provider_opts),
      do: model

  def resolve_model(model) do
    raise ArgumentError,
          "invalid model input #{inspect(model)}. " <>
            "Expected a model alias, string spec, ReqLLM tuple spec, inline model map, or %LLMDB.Model{}."
  end

  @doc """
  Returns a stable human-readable label for a model input.
  """
  @spec model_label(model_input()) :: String.t()
  def model_label(model) when is_atom(model), do: model |> resolve_model() |> model_label()
  def model_label(model) when is_binary(model), do: model

  def model_label(model) do
    case ReqLLM.model(model) do
      {:ok, %LLMDB.Model{} = normalized} -> format_model_label(normalized)
      _ -> inspect(model)
    end
  end

  @doc false
  @spec model_fingerprint_segment(model_input()) :: String.t()
  def model_fingerprint_segment(model) when is_atom(model),
    do: model |> resolve_model() |> model_fingerprint_segment()

  def model_fingerprint_segment(model) when is_binary(model), do: model

  def model_fingerprint_segment(model) do
    model
    |> fingerprint_model_term()
    |> :erlang.term_to_binary([:deterministic])
    |> Base.url_encode64(padding: false)
  end

  @doc false
  @spec provider_opt_keys(model_input()) :: %{optional(String.t()) => atom()}
  def provider_opt_keys(model) do
    with {:ok, %LLMDB.Model{} = normalized} <- ReqLLM.model(resolve_model(model)),
         provider when is_atom(provider) <- Map.get(normalized, :provider),
         {:ok, provider_mod} <- ReqLLM.provider(provider),
         true <- function_exported?(provider_mod, :provider_schema, 0) do
      provider_mod.provider_schema().schema
      |> Keyword.keys()
      |> Enum.map(&{Atom.to_string(&1), &1})
      |> Map.new()
    else
      _ -> %{}
    end
  end

  @doc """
  Thin facade for `ReqLLM.Generation.generate_text/3`.

  `opts` supports:

  - `:model` - model alias or direct model spec
  - `:system_prompt` - optional system prompt
  - `:max_tokens`, `:temperature`, `:timeout`
  - Any other ReqLLM options (e.g. `:tools`, `:tool_choice`) as pass-through options
  """
  @spec generate_text(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def generate_text(input, opts \\ []) when is_list(opts) do
    defaults = llm_defaults(:text)
    model = resolve_generation_model(opts, defaults)
    system_prompt = Keyword.get(opts, :system_prompt, defaults[:system_prompt])

    with {:ok, req_context} <- normalize_context(input, system_prompt) do
      request(:text, model, req_context.messages, build_reqllm_opts(opts, defaults))
    end
  end

  @doc """
  Thin facade for `ReqLLM.Generation.generate_object/4`.

  `opts` has the same behavior as `generate_text/2`.
  """
  @spec generate_object(term(), term(), keyword()) :: {:ok, term()} | {:error, term()}
  def generate_object(input, object_schema, opts \\ []) when is_list(opts) do
    defaults = llm_defaults(:object)
    model = resolve_generation_model(opts, defaults)
    system_prompt = Keyword.get(opts, :system_prompt, defaults[:system_prompt])

    with {:ok, req_context} <- normalize_context(input, system_prompt) do
      request(
        :object,
        model,
        req_context.messages,
        build_reqllm_opts(opts, defaults),
        object_schema
      )
    end
  end

  @doc """
  Thin facade for `ReqLLM.stream_text/3`.

  Returns ReqLLM stream response directly.
  """
  @spec stream_text(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def stream_text(input, opts \\ []) when is_list(opts) do
    defaults = llm_defaults(:stream)
    model = resolve_generation_model(opts, defaults)
    system_prompt = Keyword.get(opts, :system_prompt, defaults[:system_prompt])

    with {:ok, req_context} <- normalize_context(input, system_prompt) do
      request(:stream, model, req_context.messages, build_reqllm_opts(opts, defaults))
    end
  end

  @doc false
  def request(kind, model, messages, options, schema, context),
    do: Jido.AI.Quota.track(context, fn -> request(kind, model, messages, options, schema) end)

  @doc false
  def request(kind, model, messages, options, schema \\ nil)

  def request(kind, model, messages, options, schema) do
    case Jido.AI.Test.ReActScript.request(kind, messages, options, fn mock_model, mock_options ->
           provider_request(kind, mock_model, messages, mock_options, schema)
         end) do
      :not_scripted -> provider_request(kind, model, messages, options, schema)
      scripted -> scripted
    end
  end

  defp provider_request(:text, model, messages, options, _),
    do: ReqLLM.Generation.generate_text(model, messages, options)

  defp provider_request(:embedding, model, texts, options, _),
    do: ReqLLM.Embedding.embed(model, texts, options)

  defp provider_request(:object, model, messages, options, schema),
    do: ReqLLM.Generation.generate_object(model, messages, schema, options)

  defp provider_request(:stream, model, messages, options, _),
    do: ReqLLM.stream_text(model, messages, options)

  defp provider_request(:stream_object, model, messages, options, schema),
    do: ReqLLM.stream_object(model, messages, schema, options)

  defp resolve_generation_model(opts, defaults) do
    opts
    |> Keyword.get(:model, defaults[:model] || :fast)
    |> resolve_model()
  end

  defp normalize_context(input, system_prompt) when system_prompt in [nil, ""] do
    Context.normalize(input)
  end

  defp normalize_context(input, system_prompt) when is_binary(system_prompt) do
    Context.normalize(input, system_prompt: system_prompt)
  end

  defp build_reqllm_opts(opts, defaults) do
    req_opts =
      []
      |> put_opt(:max_tokens, Keyword.get(opts, :max_tokens, defaults[:max_tokens]))
      |> put_opt(:temperature, Keyword.get(opts, :temperature, defaults[:temperature]))
      |> put_timeout_opt(Keyword.get(opts, :timeout, defaults[:timeout]))

    passthrough_opts =
      Keyword.drop(opts, [:model, :system_prompt, :max_tokens, :temperature, :timeout, :opts])

    extra_opts = Keyword.get(opts, :opts, [])

    req_opts
    |> Keyword.merge(passthrough_opts)
    |> merge_extra_opts(extra_opts)
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp put_timeout_opt(opts, nil), do: opts
  defp put_timeout_opt(opts, timeout), do: Keyword.put(opts, :receive_timeout, timeout)

  defp merge_extra_opts(opts, extra_opts) when is_list(extra_opts),
    do: Keyword.merge(opts, extra_opts)

  defp merge_extra_opts(opts, _), do: opts

  defp format_model_label(%LLMDB.Model{} = model) do
    provider = Map.get(model, :provider)
    model_id = Map.get(model, :model) || Map.get(model, :id)

    cond do
      is_atom(provider) and is_binary(model_id) -> "#{provider}:#{model_id}"
      is_binary(provider) and is_binary(model_id) -> "#{provider}:#{model_id}"
      true -> inspect(model)
    end
  end

  defp fingerprint_model_term(model) do
    case ReqLLM.model(model) do
      {:ok, %LLMDB.Model{} = normalized} ->
        normalized
        |> Map.from_struct()
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      _ ->
        model
    end
  end
end
