defmodule Jido.AI.Middleware.Context do
  @moduledoc """
  Context struct for middleware pipeline execution.

  Contains request/response information and metadata that flows through
  the middleware chain. Provides helper functions for updating context fields.

  ## Fields

    * `:phase` - Current phase: `:request` or `:response`
    * `:model` - The model being used for the AI request
    * `:body` - Request or response body data
    * `:opts` - Options passed to the generation function
    * `:meta` - Metadata for tracking metrics, timing, etc.
    * `:private` - Private storage for middleware internal use

  ## Examples

      iex> model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}
      iex> ctx = Context.new(:request, model, %{messages: []}, [])
      iex> ctx.phase
      :request

      iex> ctx = Context.put_meta(ctx, :start_time, System.monotonic_time())
      iex> Context.get_meta(ctx, :start_time)

      iex> ctx = Context.put_private(ctx, :custom_data, "value")
      iex> Context.get_private(ctx, :custom_data)
      "value"
  """

  use TypedStruct

  alias Jido.AI.Model

  @type phase :: :request | :response

  typedstruct do
    field(:phase, phase(), enforce: true)
    field(:model, Model.t(), enforce: true)
    field(:body, map(), enforce: true)
    field(:opts, keyword(), enforce: true)
    field(:meta, map(), default: %{})
    field(:private, map(), default: %{})
  end

  @doc """
  Creates a new context for the given phase.

  ## Examples

      iex> model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}
      iex> ctx = Context.new(:request, model, %{messages: []}, [temperature: 0.7])
      iex> ctx.phase
      :request
  """
  @spec new(phase(), Model.t(), map(), keyword()) :: t()
  def new(phase, model, body, opts) do
    %__MODULE__{
      phase: phase,
      model: model,
      body: body,
      opts: opts,
      meta: %{},
      private: %{}
    }
  end

  @doc """
  Updates the phase of the context.

  ## Examples

      iex> ctx = Context.new(:request, model, %{}, [])
      iex> ctx = Context.put_phase(ctx, :response)
      iex> ctx.phase
      :response
  """
  @spec put_phase(t(), phase()) :: t()
  def put_phase(%__MODULE__{} = context, phase) do
    %{context | phase: phase}
  end

  @doc """
  Updates the body of the context.

  ## Examples

      iex> ctx = Context.new(:request, model, %{}, [])
      iex> ctx = Context.put_body(ctx, %{messages: [%{role: "user", content: "Hello"}]})
      iex> ctx.body
      %{messages: [%{role: "user", content: "Hello"}]}
  """
  @spec put_body(t(), map()) :: t()
  def put_body(%__MODULE__{} = context, body) do
    %{context | body: body}
  end

  @doc """
  Updates the opts of the context.

  ## Examples

      iex> ctx = Context.new(:request, model, %{}, [])
      iex> ctx = Context.put_opts(ctx, [temperature: 0.5, max_tokens: 100])
      iex> ctx.opts
      [temperature: 0.5, max_tokens: 100]
  """
  @spec put_opts(t(), keyword()) :: t()
  def put_opts(%__MODULE__{} = context, opts) do
    %{context | opts: opts}
  end

  @doc """
  Adds or updates a metadata key-value pair.

  ## Examples

      iex> ctx = Context.new(:request, model, %{}, [])
      iex> ctx = Context.put_meta(ctx, :request_id, "req-123")
      iex> Context.get_meta(ctx, :request_id)
      "req-123"
  """
  @spec put_meta(t(), atom() | String.t(), any()) :: t()
  def put_meta(%__MODULE__{} = context, key, value) do
    %{context | meta: Map.put(context.meta, key, value)}
  end

  @doc """
  Gets a metadata value by key.

  Returns `nil` if the key doesn't exist, or the provided default value.

  ## Examples

      iex> ctx = Context.put_meta(ctx, :custom, "value")
      iex> Context.get_meta(ctx, :custom)
      "value"

      iex> Context.get_meta(ctx, :missing)
      nil

      iex> Context.get_meta(ctx, :missing, "default")
      "default"
  """
  @spec get_meta(t(), atom() | String.t(), any()) :: any()
  def get_meta(%__MODULE__{} = context, key, default \\ nil) do
    Map.get(context.meta, key, default)
  end

  @doc """
  Adds or updates a private key-value pair for middleware internal use.

  Private storage is intended for middleware-specific data that shouldn't
  be exposed to users.

  ## Examples

      iex> ctx = Context.new(:request, model, %{}, [])
      iex> ctx = Context.put_private(ctx, :internal_state, %{step: 1})
      iex> Context.get_private(ctx, :internal_state)
      %{step: 1}
  """
  @spec put_private(t(), atom() | String.t(), any()) :: t()
  def put_private(%__MODULE__{} = context, key, value) do
    %{context | private: Map.put(context.private, key, value)}
  end

  @doc """
  Gets a private value by key.

  Returns `nil` if the key doesn't exist, or the provided default value.

  ## Examples

      iex> ctx = Context.put_private(ctx, :cache_key, "abc123")
      iex> Context.get_private(ctx, :cache_key)
      "abc123"

      iex> Context.get_private(ctx, :missing)
      nil

      iex> Context.get_private(ctx, :missing, "default")
      "default"
  """
  @spec get_private(t(), atom() | String.t(), any()) :: any()
  def get_private(%__MODULE__{} = context, key, default \\ nil) do
    Map.get(context.private, key, default)
  end

  @doc """
  Merges metadata from another map into the context.

  ## Examples

      iex> ctx = Context.new(:request, model, %{}, [])
      iex> ctx = Context.merge_meta(ctx, %{start_time: 123, user_id: "user-1"})
      iex> Context.get_meta(ctx, :start_time)
      123
      iex> Context.get_meta(ctx, :user_id)
      "user-1"
  """
  @spec merge_meta(t(), map()) :: t()
  def merge_meta(%__MODULE__{} = context, meta) when is_map(meta) do
    %{context | meta: Map.merge(context.meta, meta)}
  end

  @doc """
  Merges private data from another map into the context.

  ## Examples

      iex> ctx = Context.new(:request, model, %{}, [])
      iex> ctx = Context.merge_private(ctx, %{cache: %{}, state: :init})
      iex> Context.get_private(ctx, :state)
      :init
  """
  @spec merge_private(t(), map()) :: t()
  def merge_private(%__MODULE__{} = context, private) when is_map(private) do
    %{context | private: Map.merge(context.private, private)}
  end
end
