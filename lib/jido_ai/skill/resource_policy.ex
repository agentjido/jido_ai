defmodule Jido.AI.Skill.ResourcePolicy do
  @moduledoc """
  Defines limits for skill resource listing and loading.

  A policy bounds file count, directory traversal, the encoded general-resource
  list, file size, and text returned to model context. Binary content is
  rejected by the text API.
  """

  @default_max_resources 256
  @default_max_depth 8
  @default_max_directories 1_024
  @default_max_listing_bytes 65_536
  @default_max_file_bytes 1_048_576
  @default_max_text_bytes 262_144
  @allowed_keys [
    :max_resources,
    :max_depth,
    :max_directories,
    :max_listing_bytes,
    :max_file_bytes,
    :max_text_bytes,
    :binary
  ]

  defstruct max_resources: @default_max_resources,
            max_depth: @default_max_depth,
            max_directories: @default_max_directories,
            max_listing_bytes: @default_max_listing_bytes,
            max_file_bytes: @default_max_file_bytes,
            max_text_bytes: @default_max_text_bytes,
            binary: :reject

  @type t :: %__MODULE__{
          max_resources: pos_integer(),
          max_depth: non_neg_integer(),
          max_directories: pos_integer(),
          max_listing_bytes: pos_integer(),
          max_file_bytes: pos_integer(),
          max_text_bytes: pos_integer(),
          binary: :reject
        }

  @doc """
  Returns the default resource policy.
  """
  @spec default() :: t()
  def default, do: %__MODULE__{}

  @doc """
  Builds and validates a resource policy.

  The input can be a policy, a keyword list, or a map with atom keys.
  """
  @spec new(t() | keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = policy), do: validate(policy)

  def new(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts |> Map.new() |> new()
    else
      {:error, {:invalid_resource_policy, :options}}
    end
  end

  def new(opts) when is_map(opts) do
    unknown_keys = Map.keys(opts) -- @allowed_keys

    case unknown_keys do
      [] ->
        default()
        |> Map.from_struct()
        |> Map.merge(opts)
        |> then(&struct!(__MODULE__, &1))
        |> validate()

      [key | _rest] ->
        {:error, {:invalid_resource_policy, key}}
    end
  rescue
    _error -> {:error, {:invalid_resource_policy, :options}}
  end

  def new(_opts), do: {:error, {:invalid_resource_policy, :options}}

  @doc """
  Converts a policy to a plain map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = policy), do: Map.from_struct(policy)

  defp validate(%__MODULE__{} = policy) do
    checks = [
      max_resources: positive?(policy.max_resources),
      max_depth: non_negative?(policy.max_depth),
      max_directories: positive?(policy.max_directories),
      max_listing_bytes: positive?(policy.max_listing_bytes),
      max_file_bytes: positive?(policy.max_file_bytes),
      max_text_bytes: positive?(policy.max_text_bytes),
      binary: policy.binary == :reject
    ]

    case Enum.find(checks, fn {_key, valid?} -> not valid? end) do
      nil -> {:ok, policy}
      {key, false} -> {:error, {:invalid_resource_policy, key}}
    end
  end

  defp positive?(value), do: is_integer(value) and value > 0
  defp non_negative?(value), do: is_integer(value) and value >= 0
end
