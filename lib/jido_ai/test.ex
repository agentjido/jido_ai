defmodule Jido.AI.Test do
  @moduledoc """
  Public test helpers for deterministic Jido.AI ReAct tests.

  `expect_react/1` scripts the model boundary while the application still runs
  its real ReAct runtime, tools, event projection, and assertions.

      expect_react do
        user "summarize README"
        call "read", %{path: "README.md"}
        answer "README says Hello."
      end

  The script is registered for the current test process tree and matched by the
  latest user prompt. For code that starts agents outside that tree, pass the
  returned script explicitly:

      script =
        expect_react do
          user "summarize README"
          answer "README says Hello."
        end

      MyAgent.ask_sync(pid, "summarize README", react_opts(script))
  """

  import ExUnit.Assertions

  alias Jido.AI.Test.ReActScript

  @builder_key {__MODULE__, :react_script_builder}

  @doc """
  Starts a deterministic ReAct script and registers it for the current test.
  """
  defmacro expect_react(do: block) do
    quote do
      Jido.AI.Test.__start_react_script__()

      try do
        unquote(block)
        Jido.AI.Test.__finish_react_script__()
      after
        Jido.AI.Test.__clear_react_script_builder__()
      end
    end
  end

  @doc """
  Adds the expected initial user prompt for a ReAct test script.
  """
  @spec user(term()) :: :ok
  def user(content) do
    update_builder!(fn
      %{user: nil} = builder -> %{builder | user: content}
      %{user: _existing} -> raise ArgumentError, "react test script can only define one user/1 prompt"
    end)
  end

  @doc """
  Adds a scripted model tool call.
  """
  @spec call(String.t() | atom(), map(), keyword()) :: :ok
  def call(name, arguments, opts \\ []) when is_map(arguments) and is_list(opts) do
    add_turn!(%{type: :tool_call, name: name, arguments: arguments, opts: opts})
  end

  @doc """
  Adds the final scripted model answer.
  """
  @spec answer(term(), keyword()) :: :ok
  def answer(text, opts \\ []) when is_list(opts) do
    add_turn!(%{type: :answer, text: text, opts: opts})
  end

  @doc """
  Adds a terminal scripted model failure.
  """
  @spec fail(term(), keyword()) :: :ok
  def fail(reason, opts \\ []) when is_list(opts) do
    add_turn!(%{type: :fail, reason: reason, opts: opts})
  end

  @doc """
  Returns ReAct runtime opts for an explicit script.
  """
  @spec react_opts(ReActScript.t()) :: keyword()
  def react_opts(%ReActScript{} = script), do: ReActScript.react_opts(script)

  @doc """
  Returns ReqLLM generation opts for an explicit script.
  """
  @spec react_llm_opts(ReActScript.t()) :: keyword()
  def react_llm_opts(%ReActScript{} = script), do: ReActScript.llm_opts(script)

  @doc """
  Clears scripts registered by the current test process tree.
  """
  @spec reset_react_scripts() :: :ok
  def reset_react_scripts, do: ReActScript.clear_current_owner()

  @doc """
  Asserts that a collected ReAct result or event list ended with `expected`.
  """
  @spec assert_final_answer(map() | [map()], String.t() | Regex.t()) :: map() | [map()]
  def assert_final_answer(source, expected) when is_binary(expected) do
    assert final_answer(source) == expected
    source
  end

  def assert_final_answer(source, %Regex{} = expected) do
    assert final_answer(source) =~ expected
    source
  end

  @doc """
  Asserts that the ReAct trace includes a model-requested tool call.
  """
  @spec assert_tool_called(map() | [map()], String.t() | atom(), map() | :any) :: map() | [map()]
  def assert_tool_called(source, name, expected_args \\ :any) do
    name = to_string(name)

    assert Enum.any?(tool_calls(source), fn call ->
             call_name(call) == name and args_match?(call_args(call), expected_args)
           end)

    source
  end

  @doc """
  Asserts that a ReAct trace has no terminal runtime failure or cancellation.
  """
  @spec assert_no_runtime_failure(map() | [map()]) :: map() | [map()]
  def assert_no_runtime_failure(source) do
    refute Enum.any?(events(source), &(&1.kind in [:request_failed, :request_cancelled]))
    source
  end

  @doc false
  def __start_react_script__ do
    case Process.get(@builder_key) do
      nil -> Process.put(@builder_key, %{user: nil, turns: []})
      _builder -> raise ArgumentError, "nested expect_react blocks are not supported"
    end

    :ok
  end

  @doc false
  def __finish_react_script__ do
    builder = current_builder!()
    script = ReActScript.new(builder)
    ReActScript.register(script)
  end

  @doc false
  def __clear_react_script_builder__ do
    Process.delete(@builder_key)
    :ok
  end

  defp add_turn!(turn) do
    update_builder!(fn builder -> %{builder | turns: builder.turns ++ [turn]} end)
  end

  defp update_builder!(fun) when is_function(fun, 1) do
    builder = current_builder!()
    Process.put(@builder_key, fun.(builder))
    :ok
  end

  defp current_builder! do
    Process.get(@builder_key) || raise ArgumentError, "user/call/answer/fail must be called inside expect_react"
  end

  defp final_answer(source) do
    case source do
      %{result: result} when is_binary(result) ->
        result

      %{trace: trace} ->
        final_answer(trace)

      events when is_list(events) ->
        events
        |> Enum.reverse()
        |> Enum.find_value("", fn
          %{kind: :request_completed, data: data} -> Map.get(data, :result, "")
          _event -> nil
        end)

      _other ->
        ""
    end
  end

  defp tool_calls(source) do
    source
    |> events()
    |> Enum.flat_map(fn
      %{kind: :llm_completed, data: %{turn_type: :tool_calls, tool_calls: calls}} when is_list(calls) -> calls
      %{kind: :llm_completed, data: %{"turn_type" => :tool_calls, "tool_calls" => calls}} when is_list(calls) -> calls
      _event -> []
    end)
  end

  defp events(%{trace: trace}) when is_list(trace), do: trace
  defp events(events) when is_list(events), do: events
  defp events(_other), do: []

  defp call_name(%{name: name}), do: to_string(name)
  defp call_name(%{"name" => name}), do: to_string(name)
  defp call_name(_call), do: nil

  defp call_args(%{arguments: args}) when is_map(args), do: args
  defp call_args(%{"arguments" => args}) when is_map(args), do: args
  defp call_args(_call), do: %{}

  defp args_match?(_actual, :any), do: true
  defp args_match?(actual, expected) when is_map(expected), do: normalize_map(actual) == normalize_map(expected)
  defp args_match?(_actual, _expected), do: false

  defp normalize_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
