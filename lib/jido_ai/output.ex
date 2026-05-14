defmodule Jido.AI.Output do
  @moduledoc """
  Structured final-output contracts for Jido.AI runtimes.

  This module validates an agent's final response against an object-shaped
  schema. It is intentionally independent from any DSL layer: callers provide a
  Zoi object/map schema or an object-shaped JSON Schema map.
  """

  alias Jido.AI.Error

  @max_retries 3
  @default_retries 1
  @default_on_validation_error :repair
  @raw_preview_bytes 500

  @type schema_kind :: :zoi | :json_schema
  @type validation_mode :: :repair | :error

  @type t :: %__MODULE__{
          schema: Zoi.schema() | map(),
          schema_kind: schema_kind(),
          retries: non_neg_integer(),
          on_validation_error: validation_mode()
        }

  defstruct [
    :schema,
    schema_kind: :zoi,
    retries: @default_retries,
    on_validation_error: @default_on_validation_error
  ]

  @doc """
  Builds a structured output contract from options.
  """
  @spec new(keyword() | map() | t() | nil) :: {:ok, t() | nil} | {:error, term()}
  def new(nil), do: {:ok, nil}
  def new(%__MODULE__{} = output), do: {:ok, output}

  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = Map.new(attrs)

    schema =
      Map.get(attrs, :schema) ||
        Map.get(attrs, "schema") ||
        Map.get(attrs, :object_schema) ||
        Map.get(attrs, "object_schema")

    retries = Map.get(attrs, :retries, Map.get(attrs, "retries", @default_retries))
    mode = Map.get(attrs, :on_validation_error, Map.get(attrs, "on_validation_error", @default_on_validation_error))

    with {:ok, schema_kind} <- schema_kind(schema),
         {:ok, retries} <- normalize_retries(retries),
         {:ok, mode} <- normalize_mode(mode),
         :ok <- validate_schema_shape(schema, schema_kind) do
      {:ok, %__MODULE__{schema: schema, schema_kind: schema_kind, retries: retries, on_validation_error: mode}}
    end
  end

  def new(other), do: {:error, "output must be a map or keyword list, got: #{inspect(other)}"}

  @doc """
  Builds a structured output contract or raises `ArgumentError`.
  """
  @spec new!(keyword() | map() | t() | nil) :: t() | nil
  def new!(attrs) do
    case new(attrs) do
      {:ok, output} -> output
      {:error, reason} -> raise ArgumentError, "invalid output config: #{inspect(reason)}"
    end
  end

  @doc """
  Validates a parsed map against the configured schema.
  """
  @spec validate(t(), term()) :: {:ok, map()} | {:error, term()}
  def validate(%__MODULE__{schema_kind: :zoi, schema: schema}, value) when is_map(value) do
    value = normalize_zoi_input(schema, value)

    case Zoi.parse(schema, value) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, other} ->
        {:error, output_error(:expected_map_result, other)}

      {:error, errors} ->
        {:error, output_error({:schema, Zoi.treefy_errors(errors)}, value)}
    end
  end

  def validate(%__MODULE__{schema_kind: :json_schema, schema: schema}, value) when is_map(value) do
    case ReqLLM.Schema.validate(value, schema) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:ok, other} ->
        {:error, output_error(:expected_map_result, other)}

      {:error, reason} ->
        {:error, output_error({:schema, reason_message(reason)}, value)}
    end
  end

  def validate(%__MODULE__{}, value), do: {:error, output_error(:expected_map, value)}

  @doc """
  Parses and validates raw model output.
  """
  @spec parse(t(), term()) :: {:ok, map()} | {:error, term()}
  def parse(%__MODULE__{} = output, %ReqLLM.Response{} = response) do
    case ReqLLM.Response.unwrap_object(response, json_repair: true) do
      {:ok, object} -> validate(output, object)
      {:error, reason} -> {:error, output_error({:parse, reason_message(reason)}, response)}
    end
  end

  def parse(%__MODULE__{} = output, value) when is_map(value) do
    validate(output, unwrap_object_map(value))
  end

  def parse(%__MODULE__{} = output, value) when is_binary(value) do
    with {:ok, decoded} <- decode_json_object(value) do
      validate(output, decoded)
    end
  end

  def parse(%__MODULE__{}, value), do: {:error, output_error(:unsupported_raw_output, value)}

  @doc """
  Repairs a raw assistant answer into the configured object shape.
  """
  @spec repair(t(), term(), term(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def repair(%__MODULE__{} = output, raw, reason, context, opts \\ []) when is_map(context) do
    repair_fun = Keyword.get(opts, :repair_fun)

    repair_fun =
      cond do
        is_function(repair_fun, 4) -> repair_fun
        is_function(repair_fun, 3) -> fn output, raw, reason, _context -> repair_fun.(output, raw, reason) end
        true -> &default_repair/4
      end

    with {:ok, repaired} <- repair_fun.(output, raw, reason, context) do
      validate(output, repaired)
    end
  rescue
    error -> {:error, output_error({:repair_exception, Exception.message(error)}, raw)}
  end

  @doc """
  Returns prompt instructions that require the final response to match the schema.
  """
  @spec instructions(t() | nil) :: String.t() | nil
  def instructions(nil), do: nil

  def instructions(%__MODULE__{} = output) do
    schema_json =
      output
      |> json_schema()
      |> Jason.encode!(pretty: true)

    """
    Structured output:
    Return the final answer as a single JSON object that matches this JSON Schema.
    Do not wrap the JSON in Markdown fences. Do not include explanatory text outside the JSON object.

    #{schema_json}
    """
    |> String.trim()
  end

  @doc """
  Adds output instructions to a ReqLLM message list.
  """
  @spec apply_instructions([map()], t() | nil) :: [map()]
  def apply_instructions(messages, nil) when is_list(messages), do: messages

  def apply_instructions(messages, %__MODULE__{} = output) when is_list(messages) do
    append_system_prompt(messages, instructions(output))
  end

  @doc """
  Converts the contract to JSON Schema.
  """
  @spec json_schema(t()) :: map()
  def json_schema(%__MODULE__{schema_kind: :json_schema, schema: schema}), do: schema
  def json_schema(%__MODULE__{schema_kind: :zoi, schema: schema}), do: ReqLLM.Schema.to_json(schema)

  @doc false
  @spec fingerprint(t() | nil) :: String.t()
  def fingerprint(nil), do: ""

  def fingerprint(%__MODULE__{} = output) do
    data = %{
      schema_kind: output.schema_kind,
      schema: json_schema(output),
      retries: output.retries,
      on_validation_error: output.on_validation_error
    }

    :crypto.hash(:sha256, :erlang.term_to_binary(data, [:deterministic]))
    |> Base.url_encode64(padding: false)
  end

  @doc false
  @spec meta(t(), atom(), term(), keyword()) :: map()
  def meta(%__MODULE__{} = output, status, raw, opts \\ []) do
    %{
      status: status,
      schema_kind: output.schema_kind,
      retries: output.retries,
      on_validation_error: output.on_validation_error,
      attempt: Keyword.get(opts, :attempt, 0),
      raw_preview: raw_preview(raw),
      error: format_meta_error(Keyword.get(opts, :error)),
      validation_error: format_meta_error(Keyword.get(opts, :validation_error))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @doc false
  @spec imported_schema?(term()) :: boolean()
  def imported_schema?(%{} = schema) do
    type = Map.get(schema, "type") || Map.get(schema, :type)
    properties = Map.get(schema, "properties") || Map.get(schema, :properties)
    type in ["object", :object] and is_map(properties)
  end

  def imported_schema?(_schema), do: false

  @doc false
  @spec raw_preview(term()) :: String.t()
  def raw_preview(value) when is_binary(value), do: String.slice(value, 0, @raw_preview_bytes)

  def raw_preview(value) do
    value
    |> sanitize_preview_value()
    |> inspect(limit: 20, printable_limit: @raw_preview_bytes)
    |> String.slice(0, @raw_preview_bytes)
  end

  defp default_repair(output, raw, reason, context) do
    model = Map.get(context, :model)

    if is_nil(model) do
      {:error, output_error(:missing_repair_model, raw)}
    else
      messages = [
        %{
          role: :system,
          content:
            "Extract a JSON object that matches the provided schema from the assistant answer. Return only the structured object."
        },
        %{role: :user, content: repair_prompt(context, raw, reason)}
      ]

      llm_opts =
        context
        |> Map.get(:llm_opts, [])
        |> Keyword.delete(:tools)
        |> Keyword.delete(:tool_choice)
        |> Keyword.put(:stream, false)

      case ReqLLM.Generation.generate_object(model, messages, output.schema, llm_opts) do
        {:ok, response} ->
          unwrap_generated_response(response)

        {:error, error} ->
          {:error, output_error({:repair_failed, reason_message(error)}, raw)}
      end
    end
  end

  defp repair_prompt(context, raw, reason) do
    """
    Original user message:
    #{Map.get(context, :user_message, "")}

    Assistant answer:
    #{raw_preview(raw)}

    Validation error:
    #{reason_message(reason)}
    """
  end

  defp unwrap_generated_response(%ReqLLM.Response{} = response) do
    ReqLLM.Response.unwrap_object(response, json_repair: true)
  end

  defp unwrap_object_map(%{object: object}) when is_map(object), do: object
  defp unwrap_object_map(%{"object" => object}) when is_map(object), do: object
  defp unwrap_object_map(map), do: map

  defp append_system_prompt(messages, nil), do: messages

  defp append_system_prompt([%{role: role, content: content} = first | rest], addition)
       when role in [:system, "system"] and is_binary(content) do
    [%{first | content: join_prompt(content, addition)} | rest]
  end

  defp append_system_prompt([%{"role" => role, "content" => content} = first | rest], addition)
       when role in [:system, "system"] and is_binary(content) do
    [Map.put(first, "content", join_prompt(content, addition)) | rest]
  end

  defp append_system_prompt(messages, addition), do: [%{role: :system, content: addition} | messages]

  defp join_prompt("", addition), do: addition
  defp join_prompt(prompt, addition), do: prompt <> "\n\n" <> addition

  defp decode_json_object(value) do
    value
    |> strip_markdown_fence()
    |> Jason.decode()
    |> case do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, other} -> {:error, output_error(:expected_map, other)}
      {:error, error} -> {:error, output_error({:parse, reason_message(error)}, value)}
    end
  end

  defp strip_markdown_fence(value) do
    trimmed = String.trim(value)

    case Regex.run(~r/\A```[^\n]*\n?(.*?)\s*```\z/s, trimmed) do
      [_, inner] -> String.trim(inner)
      _other -> trimmed
    end
  end

  defp schema_kind(schema) do
    cond do
      zoi_schema?(schema) -> {:ok, :zoi}
      imported_schema?(schema) -> {:ok, :json_schema}
      true -> {:error, "output schema must be a Zoi object schema or imported JSON object schema"}
    end
  end

  defp validate_schema_shape(schema, :zoi) do
    if Zoi.Type.impl_for(schema) == Zoi.Type.Zoi.Types.Map do
      :ok
    else
      {:error, "output schema must be a Zoi object/map schema"}
    end
  end

  defp validate_schema_shape(schema, :json_schema) do
    if imported_schema?(schema) do
      :ok
    else
      {:error, "imported output schema must be a JSON Schema object with properties"}
    end
  end

  defp normalize_retries(value) when is_integer(value) and value >= 0, do: {:ok, min(value, @max_retries)}

  defp normalize_retries(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> normalize_retries(integer)
      _other -> {:error, "output retries must be a non-negative integer"}
    end
  end

  defp normalize_retries(_value), do: {:error, "output retries must be a non-negative integer"}

  defp normalize_mode(value) when value in [:repair, "repair"], do: {:ok, :repair}
  defp normalize_mode(value) when value in [:error, "error"], do: {:ok, :error}
  defp normalize_mode(_value), do: {:error, "output on_validation_error must be :repair or :error"}

  defp zoi_schema?(schema), do: is_struct(schema) and not is_nil(Zoi.Type.impl_for(schema))

  defp normalize_zoi_input(%Zoi.Types.Map{fields: fields}, value) when is_map(value) do
    fields = Map.new(fields)

    field_map =
      Map.new(fields, fn {field, _schema} ->
        {to_string(field), field}
      end)

    Map.new(value, fn {key, field_value} ->
      normalized_key =
        if is_binary(key) do
          Map.get(field_map, key, key)
        else
          key
        end

      field_schema = Map.get(fields, normalized_key)
      {normalized_key, normalize_zoi_input(field_schema, field_value)}
    end)
  end

  defp normalize_zoi_input(%Zoi.Types.Enum{enum_type: :atom, values: values}, value) when is_binary(value) do
    values
    |> Map.new(fn
      {label, atom} -> {to_string(label), atom}
      atom when is_atom(atom) -> {Atom.to_string(atom), atom}
    end)
    |> Map.get(value, value)
  end

  defp normalize_zoi_input(_schema, value), do: value

  defp output_error(reason, raw) do
    %Error.Validation.Output{
      field: :output,
      message: "Structured output validation failed",
      details: %{reason: reason, raw_preview: raw_preview(raw)}
    }
  end

  defp format_meta_error(nil), do: nil
  defp format_meta_error(%{details: details}), do: sanitize_preview_value(details)
  defp format_meta_error(reason), do: inspect(reason, limit: 20, printable_limit: @raw_preview_bytes)

  defp reason_message(%{__exception__: true} = error), do: Exception.message(error)
  defp reason_message(reason), do: inspect(reason, limit: 20, printable_limit: @raw_preview_bytes)

  defp sanitize_preview_value(value), do: Jido.AI.Observe.sanitize_sensitive(value)
end
