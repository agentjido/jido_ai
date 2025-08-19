defmodule Jido.AI.Provider.Base do
  @moduledoc """
  Compatibility layer for the old Base provider module.

  This module maintains backward compatibility while delegating to the new
  modular architecture. This allows existing tests and providers to continue
  working while we gradually migrate to the new structure.

  **This module is deprecated and will be removed in a future version.**
  Use `Jido.AI.Provider.Macro` instead.
  """

  # This is a compatibility layer only

  alias Jido.AI.Error
  alias Jido.AI.Message
  alias Jido.AI.Model
  alias Jido.AI.Provider
  alias Jido.AI.Provider.OpenAI
  alias Jido.AI.Provider.Request.Builder
  alias Jido.AI.Provider.Request.HTTP
  alias Jido.AI.Provider.Response.Parser
  alias Jido.AI.Provider.Util.Options

  # Re-export all the callbacks from Behaviour
  @callback provider_info() :: Provider.t()
  @callback api_url() :: String.t()
  @callback supports_json_mode?() :: boolean()
  @callback generate_text(Model.t(), String.t() | [Message.t()], keyword()) ::
              {:ok, String.t()} | {:error, Error.t()}
  @callback stream_text(Model.t(), String.t() | [Message.t()], keyword()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}
  @callback generate_object(Model.t(), String.t() | [Message.t()], map(), keyword()) ::
              {:ok, map()} | {:error, Error.t()}
  @callback stream_object(Model.t(), String.t() | [Message.t()], map(), keyword()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}

  # Handle the __using__ macro delegation
  defmacro __using__(opts) do
    quote do
      use Jido.AI.Provider.Macro, unquote(opts)
    end
  end

  # Delegate all the public functions to their new homes
  defdelegate default_generate_text(provider_module, model, prompt, opts \\ []), to: Jido.AI.Provider.Macro
  defdelegate default_stream_text(provider_module, model, prompt, opts \\ []), to: Jido.AI.Provider.Macro
  defdelegate default_generate_object(provider_module, model, prompt, schema, opts \\ []), to: Jido.AI.Provider.Macro
  defdelegate default_stream_object(provider_module, model, prompt, schema, opts \\ []), to: Jido.AI.Provider.Macro

  defdelegate merge_model_options(provider_module, model, opts), to: Options
  defdelegate merge_provider_options(model, prompt, function_opts, provider_opts), to: Options
  defdelegate do_http_request(provider_module, model, request_body, opts), to: HTTP
  defdelegate do_stream_request(provider_module, model, request_body, opts), to: HTTP
  # Compatibility wrappers that maintain the old return format
  def extract_text_response(response) do
    case Parser.extract_text_response(response) do
      {:ok, text, _meta} -> {:ok, text}
      error -> error
    end
  end

  def extract_object_response(response) do
    case Parser.extract_object_response(response) do
      {:ok, object, _meta} -> {:ok, object}
      error -> error
    end
  end

  defdelegate encode_messages(prompt), to: Builder
  defdelegate encode_message(message), to: Builder
  defdelegate build_retry_prompt(original_prompt, schema, error), to: Jido.AI.Provider.Macro

  @doc """
  Builds chat completion request body for backward compatibility.

  **Deprecated**: Use `Jido.AI.Provider.Request.Builder.build_chat_completion_body/5` instead.
  """
  @spec build_chat_completion_body(Model.t(), String.t() | [Message.t()], String.t() | nil, keyword()) :: map()
  def build_chat_completion_body(%Model{} = model, prompt, system_prompt, opts) do
    # Use OpenAI as the default provider for backward compatibility
    Builder.build_chat_completion_body(
      OpenAI,
      model,
      prompt,
      system_prompt,
      opts
    )
  end
end
