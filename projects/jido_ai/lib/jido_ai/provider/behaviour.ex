defmodule Jido.AI.Provider.Behaviour do
  @moduledoc """
  Defines the behaviour for AI provider modules.

  All provider modules must implement these callbacks to provide a consistent
  interface for AI text and object generation.
  """

  alias Jido.AI.{Error, Message, Model, Provider}

  @doc "Returns provider information"
  @callback provider_info() :: Provider.t()

  @doc "Returns the API URL for this provider"
  @callback api_url() :: String.t()

  @doc "Returns true if provider supports native JSON response formatting"
  @callback supports_json_mode?() :: boolean()

  @doc "Returns the list of supported chat completion options"
  @callback chat_completion_opts() :: [atom()]

  @doc "Returns the stream event format type for this provider"
  @callback stream_event_type() :: :openai | :anthropic | :other

  @doc "Generates text from a Model and prompt"
  @callback generate_text(Model.t(), String.t() | [Message.t()], keyword()) ::
              {:ok, String.t()} | {:error, Error.t()}

  @doc "Streams text from a Model and prompt, returning an Elixir Stream"
  @callback stream_text(Model.t(), String.t() | [Message.t()], keyword()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}

  @doc "Generates structured data from a Model, prompt, and schema"
  @callback generate_object(Model.t(), String.t() | [Message.t()], map(), keyword()) ::
              {:ok, map()} | {:error, Error.t()}

  @doc "Streams structured data from a Model, prompt, and schema, returning an Elixir Stream"
  @callback stream_object(Model.t(), String.t() | [Message.t()], map(), keyword()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}

  @doc "Builds chat completion request body (overridable for provider-specific formats)"
  @callback build_chat_completion_body(Model.t(), String.t() | [Message.t()], String.t() | nil, keyword()) :: map()

  @optional_callbacks [build_chat_completion_body: 4]
end
