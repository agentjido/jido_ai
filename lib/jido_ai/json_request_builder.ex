defmodule Jido.AI.JsonRequestBuilder do
  @moduledoc """
  Builds ReqLLM requests with JSON mode and schema guidance.

  This module helps configure LLM requests to produce structured JSON
  output that matches defined schemas. It handles provider-specific
  JSON mode settings and includes schema information in prompts.

  ## JSON Mode Support by Provider

  - **OpenAI**: Native JSON mode via `response_format: %{type: "json_object"}`
  - **Anthropic**: Supports JSON mode through system prompts and formatting
  - **Google**: JSON mode support varies by model
  - **Others**: Most modern LLM providers support JSON output through prompts

  ## Usage

      schema = Jido.AI.Schemas.ChatResponseSchema
      enhanced_prompt = JsonRequestBuilder.add_schema_to_prompt(prompt, schema)
      options = JsonRequestBuilder.build_json_options(schema)

      # Use in ReqLLM request
      ReqLLM.ChatCompletion.run(model, enhanced_prompt, options)
  """

  alias Jido.AI.Prompt
  alias Jido.AI.Prompt.MessageItem
  alias Jido.AI.Schema

  @doc """
  Build options map for ReqLLM with JSON mode enabled.

  Adds `response_format` to force JSON output from supported providers.

  ## Options

  - `schema` - The schema module to use for generating JSON schema spec
  - `base_opts` - Existing options to merge with (default: [])

  ## Example

      iex> opts = JsonRequestBuilder.build_json_options(MySchema)
      [response_format: %{type: "json_object"}]
  """
  def build_json_options(schema_module, base_opts \\ []) when is_atom(schema_module) do
    json_opts = [
      response_format: %{type: "json_object"}
    ]

    Keyword.merge(base_opts, json_opts)
  end

  @doc """
  Add schema information to a prompt to guide LLM output.

  This adds a system message containing the JSON schema and format
  instructions to help the LLM produce correctly formatted output.

  ## Example

      prompt = Prompt.new(:user, "What is 2 + 2?")
      enhanced = JsonRequestBuilder.add_schema_to_prompt(prompt, MySchema)
  """
  def add_schema_to_prompt(%Prompt{} = prompt, schema_module) do
    schema_prompt = Schema.to_prompt_format(schema_module)

    system_msg = %MessageItem{
      role: :system,
      content: """
      You must respond with valid JSON that matches the following schema.

      #{schema_prompt}

      Important:
      - Your response must be valid JSON
      - Include all required fields
      - Use the correct types for each field
      - Do not include any text outside the JSON object
      """,
      engine: :none
    }

    # Prepend system message to existing messages
    %{prompt | messages: [system_msg | prompt.messages]}
  end

  def add_schema_to_prompt(prompt_string, schema_module) when is_binary(prompt_string) do
    prompt = Prompt.new(:user, prompt_string)
    add_schema_to_prompt(prompt, schema_module)
  end

  @doc """
  Generate JSON schema for inclusion in API requests.

  Some providers (like OpenAI function calling) accept JSON schema directly
  in the request parameters. This generates that schema.

  ## Example

      iex> json_schema = JsonRequestBuilder.to_json_schema(MySchema)
      %{
        "type" => "object",
        "properties" => %{"field" => %{"type" => "string"}},
        "required" => ["field"]
      }
  """
  def to_json_schema(schema_module) do
    Schema.to_json_schema(schema_module)
  end

  @doc """
  Build complete request options with schema and JSON mode.

  Combines schema prompt enhancement, JSON mode options, and any
  additional parameters into a complete configuration.

  ## Options

  - `:temperature` - Sampling temperature (default: 0.7)
  - `:max_tokens` - Maximum tokens in response (default: 1000)
  - `:top_p` - Nucleus sampling parameter
  - `:stop` - Stop sequences

  ## Example

      {enhanced_prompt, opts} = JsonRequestBuilder.build_request(
        prompt,
        MySchema,
        temperature: 0.5,
        max_tokens: 500
      )
  """
  def build_request(prompt, schema_module, additional_opts \\ []) do
    enhanced_prompt = add_schema_to_prompt(prompt, schema_module)

    opts =
      additional_opts
      |> Keyword.put(:response_format, %{type: "json_object"})

    {enhanced_prompt, opts}
  end

  @doc """
  Check if a provider supports native JSON mode.

  Returns true if the provider has native JSON mode support via
  response_format parameter.

  ## Example

      iex> JsonRequestBuilder.supports_json_mode?(:openai)
      true

      iex> JsonRequestBuilder.supports_json_mode?(:unknown)
      false
  """
  def supports_json_mode?(provider) when is_atom(provider) do
    # Known providers with native JSON mode support
    provider in [:openai, :anthropic, :google, :mistral, :groq, :together, :fireworks]
  end
end
