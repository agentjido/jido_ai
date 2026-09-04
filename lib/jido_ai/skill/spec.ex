defmodule Jido.AI.Skill.Spec do
  @moduledoc """
  Specification struct for skills, supporting compile-time modules,
  runtime-loaded SKILL.md files, and host-supplied runtime specs.

  Follows the agentskills.io spec with Jido-specific extensions.
  """

  @type source :: {:module, module()} | {:file, String.t()}
  @type body_ref :: {:file, String.t()} | {:inline, String.t()} | nil

  alias Jido.AI.Skill.{Diagnostics, Error}

  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_name_length 64
  @max_description_length 1024
  @max_compatibility_length 500

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          license: String.t() | nil,
          compatibility: String.t() | nil,
          metadata: map() | nil,
          allowed_tools: [String.t()],
          source: source() | nil,
          body_ref: body_ref(),
          actions: [module()],
          plugins: [module()],
          vsn: String.t() | nil,
          tags: [String.t()],
          diagnostics: Diagnostics.t() | nil
        }

  defstruct [
    :name,
    :description,
    :license,
    :compatibility,
    :metadata,
    allowed_tools: [],
    source: nil,
    body_ref: nil,
    actions: [],
    plugins: [],
    vsn: nil,
    tags: [],
    diagnostics: nil
  ]

  @doc """
  Validates the strict manifest fields shared by filesystem and runtime specs.
  """
  @spec validate_manifest(t()) :: :ok | {:error, term()}
  def validate_manifest(%__MODULE__{} = spec) do
    with :ok <- validate_name(spec.name),
         :ok <- validate_description(spec.description),
         :ok <- validate_license(spec.license),
         :ok <- validate_compatibility(spec.compatibility),
         :ok <- validate_metadata(spec.metadata) do
      validate_allowed_tools(spec.allowed_tools)
    end
  end

  def validate_manifest(_spec), do: {:error, :expected_spec}

  @doc """
  Validates a runtime-provided skill spec for Agent Skills integration.

  Runtime specs must use `source: nil` and carry their body inline so Agent
  Skills can preserve the host-provided manifest without discovering, reading,
  or listing from the filesystem.
  """
  @spec validate_runtime(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def validate_runtime(spec, opts \\ [])

  def validate_runtime(%__MODULE__{} = spec, opts) do
    index = Keyword.get(opts, :index)

    with :ok <- validate_manifest(spec),
         :ok <- validate_runtime_source(spec.source),
         :ok <- validate_inline_body(spec.body_ref) do
      {:ok, spec}
    else
      {:error, reason} -> {:error, {:invalid_runtime_skill_spec, index, reason}}
    end
  end

  def validate_runtime(_spec, opts) do
    {:error, {:invalid_runtime_skill_spec, Keyword.get(opts, :index), :expected_spec}}
  end

  defp validate_name(name) when is_binary(name) do
    cond do
      String.trim(name) == "" -> {:error, %Error.Validation.MissingField{field: :name}}
      String.length(name) > @max_name_length -> {:error, %Error.Validation.InvalidName{name: name}}
      Regex.match?(@name_regex, name) -> :ok
      true -> {:error, %Error.Validation.InvalidName{name: name}}
    end
  end

  defp validate_name(_name), do: {:error, %Error.Validation.MissingField{field: :name}}

  defp validate_description(description) when is_binary(description) do
    cond do
      String.trim(description) == "" ->
        {:error, %Error.Validation.MissingField{field: :description}}

      String.length(description) > @max_description_length ->
        {:error, %Error.Validation.InvalidField{field: :description, reason: :too_long, value: description}}

      true ->
        :ok
    end
  end

  defp validate_description(_description), do: {:error, %Error.Validation.MissingField{field: :description}}

  defp validate_license(nil), do: :ok
  defp validate_license(license) when is_binary(license), do: :ok

  defp validate_license(license),
    do: {:error, %Error.Validation.InvalidField{field: :license, reason: :invalid_type, value: license}}

  defp validate_compatibility(nil), do: :ok

  defp validate_compatibility(compatibility) when is_binary(compatibility) do
    cond do
      String.trim(compatibility) == "" ->
        {:error, %Error.Validation.InvalidField{field: :compatibility, reason: :empty, value: compatibility}}

      String.length(compatibility) > @max_compatibility_length ->
        {:error, %Error.Validation.InvalidField{field: :compatibility, reason: :too_long, value: compatibility}}

      true ->
        :ok
    end
  end

  defp validate_compatibility(compatibility),
    do: {:error, %Error.Validation.InvalidField{field: :compatibility, reason: :invalid_type, value: compatibility}}

  defp validate_metadata(nil), do: :ok
  defp validate_metadata(metadata) when is_map(metadata) and map_size(metadata) == 0, do: :ok

  defp validate_metadata(metadata) when is_map(metadata) do
    if Enum.all?(metadata, fn {key, value} -> is_binary(key) and is_binary(value) end) do
      :ok
    else
      {:error, %Error.Validation.InvalidField{field: :metadata, reason: :invalid_metadata, value: metadata}}
    end
  end

  defp validate_metadata(metadata),
    do: {:error, %Error.Validation.InvalidField{field: :metadata, reason: :invalid_type, value: metadata}}

  defp validate_allowed_tools(tools) when is_list(tools) do
    if Enum.all?(tools, &is_binary/1) do
      :ok
    else
      {:error, %Error.Validation.InvalidField{field: :allowed_tools, reason: :invalid_type, value: tools}}
    end
  end

  defp validate_allowed_tools(tools),
    do: {:error, %Error.Validation.InvalidField{field: :allowed_tools, reason: :invalid_type, value: tools}}

  defp validate_runtime_source(nil), do: :ok

  defp validate_runtime_source(source),
    do: {:error, %Error.Validation.InvalidField{field: :source, reason: :must_be_nil, value: source}}

  defp validate_inline_body({:inline, body}) when is_binary(body) do
    if String.valid?(body) do
      :ok
    else
      {:error, %Error.Validation.InvalidField{field: :body_ref, reason: :invalid_utf8, value: :inline}}
    end
  end

  defp validate_inline_body(body_ref),
    do: {:error, %Error.Validation.InvalidField{field: :body_ref, reason: :inline_body_required, value: body_ref}}
end
