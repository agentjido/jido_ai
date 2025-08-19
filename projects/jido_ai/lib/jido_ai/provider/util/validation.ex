defmodule Jido.AI.Provider.Util.Validation do
  @moduledoc """
  Validation utilities for provider modules.
  """

  alias Jido.AI.Error.Invalid
  alias Jido.AI.{Message}

  @doc """
  Validates that a prompt is valid (non-empty string or valid message list).
  """
  @spec validate_prompt(String.t() | [Message.t()]) ::
          {:ok, String.t() | [Message.t()]} | {:error, struct()}
  def validate_prompt(prompt) when is_binary(prompt) and prompt != "", do: {:ok, prompt}

  def validate_prompt(messages) when is_list(messages) do
    cond do
      Enum.empty?(messages) ->
        {:error, Invalid.Parameter.exception(parameter: "prompt")}

      Enum.all?(messages, &Message.valid?/1) ->
        {:ok, messages}

      true ->
        {:error, Invalid.Parameter.exception(parameter: "prompt")}
    end
  end

  def validate_prompt(_), do: {:error, Invalid.Parameter.exception(parameter: "prompt")}

  @doc """
  Validates that a schema is a valid structure (map or keyword list).
  """
  @spec validate_schema(map() | keyword()) :: {:ok, map() | keyword()} | {:error, struct()}
  def validate_schema(schema) when (is_map(schema) and schema != %{}) or (is_list(schema) and schema != []) do
    {:ok, schema}
  end

  def validate_schema(_) do
    {:error, Invalid.Parameter.exception(parameter: "schema")}
  end

  @doc """
  Gets a required option from the options keyword list.
  """
  @spec get_required_opt(keyword(), atom()) :: {:ok, any()} | {:error, struct()}
  def get_required_opt(opts, key) do
    case opts[key] do
      nil -> {:error, Invalid.Parameter.exception(parameter: Atom.to_string(key))}
      value -> {:ok, value}
    end
  end
end
