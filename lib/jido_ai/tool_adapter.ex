defmodule Jido.AI.ToolAdapter do
  @moduledoc """
  Adapts declared Jido Actions and Flows to ReqLLM tools.

  ReqLLM describes the tool and decodes the model call. `Jido.Exec` validates
  and runs the selected Jido executable.
  """

  @type tool_spec :: %{
          required(:kind) => :action | :flow,
          required(:target) => module(),
          required(:name) => String.t(),
          required(:description) => String.t(),
          required(:timeout) => pos_integer()
        }

  @type error_reason ::
          {:invalid_tool_context, term()}
          | {:invalid_tool_target, term()}
          | {:invalid_tool_spec, term()}
          | {:duplicate_tool_name, String.t()}
          | {:request_timeout, pos_integer()}

  @doc "Converts normalized tool declarations to ReqLLM tools."
  @spec from_specs([tool_spec()], map(), keyword()) ::
          {:ok, [ReqLLM.Tool.t()]} | {:error, error_reason() | term()}
  def from_specs(specs, context \\ %{}, opts \\ [])

  def from_specs(specs, context, opts)
      when is_list(specs) and is_map(context) and is_list(opts) do
    with {:ok, deadline} <- deadline_option(opts),
         {:ok, tools} <- map_specs(specs, context, deadline),
         :ok <- unique_names(tools) do
      {:ok, tools}
    end
  end

  def from_specs(_specs, context, _opts) when not is_map(context),
    do: {:error, {:invalid_tool_context, context}}

  def from_specs(specs, _context, _opts), do: {:error, {:invalid_tool_spec, specs}}

  @doc "Converts Jido Action and Flow modules to ReqLLM tools."
  @spec from_executables([module()], map()) ::
          {:ok, [ReqLLM.Tool.t()]} | {:error, error_reason() | term()}
  def from_executables(targets, context \\ %{})

  def from_executables(targets, context) when is_list(targets) and is_map(context) do
    with {:ok, specs} <- infer_specs(targets) do
      from_specs(specs, context)
    end
  end

  def from_executables(_targets, context) when not is_map(context),
    do: {:error, {:invalid_tool_context, context}}

  def from_executables(targets, _context), do: {:error, {:invalid_tool_target, targets}}

  @doc "Converts one Jido Action or Flow module to a ReqLLM tool."
  @spec from_executable(module(), map()) :: {:ok, ReqLLM.Tool.t()} | {:error, term()}
  def from_executable(target, context \\ %{})

  def from_executable(target, context) when is_atom(target) and is_map(context) do
    with {:ok, [tool]} <- from_executables([target], context), do: {:ok, tool}
  end

  def from_executable(target, _context), do: {:error, {:invalid_tool_target, target}}

  @doc false
  @spec preflight([ReqLLM.ToolCall.t()], [ReqLLM.Tool.t()]) ::
          :ok | {:error, [ReqLLM.ToolCall.resolution()]}
  def preflight(calls, tools) when is_list(calls) and is_list(tools) do
    resolutions = Enum.map(calls, &ReqLLM.ToolCall.resolve(&1, tools))

    if Enum.all?(resolutions, &(&1.state == :valid)),
      do: :ok,
      else: {:error, resolutions}
  end

  @doc false
  @spec rejection_messages([ReqLLM.ToolCall.resolution()]) :: [ReqLLM.Message.t()]
  def rejection_messages(resolutions) do
    Enum.map(resolutions, fn resolution ->
      message =
        if resolution.state == :valid do
          "Tool batch rejected because another call is invalid"
        else
          error_message(resolution.error)
        end

      ReqLLM.Context.tool_result_message(
        resolution.name,
        resolution.id,
        %{ok: false, error: %{type: resolution.state, message: message}},
        %{is_error: true}
      )
    end)
  end

  @doc false
  def execute(spec, context, params) do
    execute(spec, context, nil, params)
  end

  @doc false
  def execute(spec, context, deadline, params) do
    # ReqLLM callbacks receive JSON-shaped maps. Jido.Exec accepts Elixir input
    # and intentionally does not decode transport keys. Zoi performs this
    # boundary conversion. Jido.Exec remains the authoritative Action or Flow
    # validation and execution boundary.
    with {:ok, params} <- decode_params(spec.target.schema(), params),
         {:ok, timeout} <- tool_timeout(spec.timeout, deadline) do
      case Jido.Exec.run(spec.target, params, context, timeout: timeout) do
        {:ok, result} -> {:ok, result}
        {:ok, result, []} -> {:ok, result}
        {:ok, _result, effects} -> {:error, {:tool_effects_not_supported, spec.name, effects}}
        {:error, reason} -> {:error, reason}
        other -> {:error, other}
      end
    end
  end

  defp map_specs(specs, context, deadline) do
    Enum.reduce_while(specs, {:ok, []}, fn spec, {:ok, tools} ->
      case from_spec(spec, context, deadline) do
        {:ok, tool} -> {:cont, {:ok, [tool | tools]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tools} -> {:ok, Enum.reverse(tools)}
      error -> error
    end
  end

  defp from_spec(
         %{
           kind: kind,
           target: target,
           name: name,
           description: description,
           timeout: timeout
         } = spec,
         context,
         deadline
       )
       when kind in [:action, :flow] and is_atom(target) and is_binary(name) and
              is_binary(description) and is_integer(timeout) and timeout > 0 do
    with {:ok, executable} <- Jido.Instruction.resolve(target),
         :ok <- Jido.Instruction.validate(executable),
         true <- executable.kind == kind do
      ReqLLM.Tool.new(
        name: name,
        description: description,
        parameter_schema: target.schema(),
        callback: {__MODULE__, :execute, [spec, context, deadline]}
      )
    else
      _other -> {:error, {:invalid_tool_spec, spec}}
    end
  end

  defp from_spec(spec, _context, _deadline), do: {:error, {:invalid_tool_spec, spec}}

  defp deadline_option(opts) do
    if Keyword.keyword?(opts) do
      case Keyword.get(opts, :deadline) do
        nil ->
          {:ok, nil}

        %{at: at, timeout: timeout} = deadline when is_integer(at) and is_integer(timeout) and timeout > 0 ->
          {:ok, deadline}

        deadline ->
          {:error, {:invalid_tool_spec, {:deadline, deadline}}}
      end
    else
      {:error, {:invalid_tool_spec, opts}}
    end
  end

  defp tool_timeout(timeout, nil), do: {:ok, timeout}

  defp tool_timeout(timeout, %{at: at, timeout: request_timeout}) do
    remaining = at - System.monotonic_time(:millisecond)

    if remaining > 0,
      do: {:ok, min(timeout, remaining)},
      else: {:error, {:request_timeout, request_timeout}}
  end

  defp infer_specs(targets) do
    Enum.reduce_while(targets, {:ok, []}, fn target, {:ok, specs} ->
      case executable_kind(target) do
        {:ok, kind} ->
          spec = %{
            kind: kind,
            target: target,
            name: target.name(),
            description: target.description() || "",
            timeout: 5_000
          }

          {:cont, {:ok, [spec | specs]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end

  defp executable_kind(target)
       when is_atom(target) and target not in [nil, true, false] do
    with {:ok, executable} <- Jido.Instruction.resolve(target),
         :ok <- Jido.Instruction.validate(executable) do
      {:ok, executable.kind}
    else
      _other -> {:error, {:invalid_tool_target, target}}
    end
  end

  defp executable_kind(target), do: {:error, {:invalid_tool_target, target}}

  defp unique_names(tools) do
    names = Enum.map(tools, & &1.name)

    case names -- Enum.uniq(names) do
      [] -> :ok
      [name | _rest] -> {:error, {:duplicate_tool_name, name}}
    end
  end

  defp decode_params([], params) when is_map(params), do: {:ok, params}

  defp decode_params(%_{} = schema, params) do
    Zoi.parse(schema, params, coerce: true)
  end

  defp decode_params(_schema, params) when is_map(params), do: {:ok, params}
  defp decode_params(_schema, params), do: {:error, {:invalid_tool_input, params}}

  defp error_message(error) when is_exception(error), do: Exception.message(error)
  defp error_message(nil), do: "Invalid tool call"
  defp error_message(error), do: inspect(error)
end
