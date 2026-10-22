defmodule Jido.AI.Actions.LLM.GenerateObject do
  @moduledoc """
  A Jido.Action for generating structured JSON objects using LLM with schema validation.

  This action wraps ReqLLM.generate_object/4 for schema-constrained generation,
  returning validated JSON objects that conform to a provided schema.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:fast`, `:capable`) or direct spec (e.g., `"anthropic:claude-haiku-4-5"`)
  * `prompt` (required) - The prompt describing what object to generate
  * `object_schema` (required) - Zoi schema or NimbleOptions keyword list defining the expected structure
  * `system_prompt` (optional) - System prompt to guide the LLM's behavior
  * `max_tokens` (optional) - Maximum tokens to generate (default: `1024`)
  * `temperature` (optional) - Sampling temperature 0.0-2.0 (default: `0.7`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic object generation with Zoi schema
      schema = Zoi.object(%{
        name: Zoi.string(),
        age: Zoi.integer(),
        occupation: Zoi.string()
      })

      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.GenerateObject, %{
        prompt: "Generate a person named Alice who is a software engineer",
        object_schema: schema
      })
      # => %{object: %{name: "Alice", age: 28, occupation: "Software Engineer"}, ...}

      # With model and system prompt
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.LLM.GenerateObject, %{
        model: :capable,
        prompt: "Generate a product review",
        object_schema: review_schema,
        system_prompt: "You are generating structured product review data.",
        temperature: 0.5
      })

  ## Result Format

      %{
        object: %{name: "Alice", age: 28, occupation: "Software Engineer"},
        model: "anthropic:claude-haiku-4-5",
        usage: %{
          input_tokens: 25,
          output_tokens: 15,
          total_tokens: 40
        }
      }
  """

  use Jido.Action,
    name: "llm_generate_object",
    description: "Generate structured data matching a JSON schema",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :fast) or direct model spec string")
          |> Zoi.optional(),
        prompt: Zoi.string(description: "The prompt describing what object to generate"),
        object_schema: Zoi.any(description: "Zoi schema or NimbleOptions keyword list"),
        system_prompt:
          Zoi.string(description: "Optional system prompt to guide the LLM's behavior")
          |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
        temperature: Zoi.float(description: "Sampling temperature (0.0-2.0)") |> Zoi.default(0.7),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  @doc "Returns the Action category."
  def category, do: "ai"

  @doc "Returns tags that classify this Action."
  def tags, do: ["llm", "structured-output", "json"]
  @doc "Returns the Action metadata version."
  def vsn, do: "1.0.0"

  @impl Jido.Action
  def on_before_validate_params(params), do: Jido.AI.ActionInput.before_validate(schema(), params)

  @impl Jido.Action
  def run(params, context),
    do: Jido.AI.Actions.LLM.Request.run(:generate_object, __MODULE__, params, context)
end
