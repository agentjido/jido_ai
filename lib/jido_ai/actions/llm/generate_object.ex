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
    category: "ai",
    tags: ["llm", "structured-output", "json"],
    vsn: "1.0.0",
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

  alias Jido.AI.Security
  alias Jido.AI.Actions.Helpers
  alias ReqLLM.Context

  @doc """
  Executes the generate_object action.

  ## Returns

  * `{:ok, result}` - Successful response with `object`, `model`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        object: %{...},
        model: "anthropic:claude-haiku-4-5",
        usage: %{
          input_tokens: 25,
          output_tokens: 15,
          total_tokens: 40
        }
      }
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, validated_params} <- Helpers.validate_and_sanitize_input(params),
         {:ok, _schema} <- validate_object_schema(validated_params[:object_schema]),
         {:ok, model} <- Helpers.resolve_model(validated_params[:model], :fast),
         {:ok, req_context} <- build_messages(validated_params[:prompt], validated_params[:system_prompt]),
         opts = Helpers.build_opts(validated_params),
         {:ok, response} <-
           ReqLLM.Generation.generate_object(
             model,
             req_context.messages,
             validated_params[:object_schema],
             opts
           ) do
      {:ok, format_result(response, model)}
    else
      {:error, reason} -> {:error, sanitize_error_for_user(reason)}
    end
  end

  defp validate_object_schema(nil), do: {:error, :object_schema_required}
  defp validate_object_schema(schema), do: {:ok, schema}

  defp sanitize_error_for_user(error) when is_struct(error) do
    Security.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(error) when is_atom(error) do
    Security.sanitize_error_message(error)
  end

  defp sanitize_error_for_user(_error), do: "An error occurred"

  defp build_messages(prompt, nil) do
    Context.normalize(prompt, [])
  end

  defp build_messages(prompt, system_prompt) when is_binary(system_prompt) do
    Context.normalize(prompt, system_prompt: system_prompt)
  end

  defp format_result(response, model) do
    %{
      object: extract_object(response),
      model: model,
      usage: Helpers.extract_usage(response)
    }
  end

  defp extract_object(%{object: object}) when is_map(object), do: object
  defp extract_object(response) when is_map(response), do: response
end
