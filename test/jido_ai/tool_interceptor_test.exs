defmodule Jido.AI.ToolInterceptorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ToolInterceptor

  defmodule NoCallbacks do
  end

  defmodule SearchAction do
    use Jido.Action,
      name: "search",
      schema: Zoi.object(%{query: Zoi.string()})

    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule BeforeOnly do
    def before_tool_call(tool_call, context) do
      send(context.test_pid, {:before_tool_call, tool_call})
      {:ok, %{tool_call | arguments: Map.put(tool_call.arguments, "tenant_id", "tenant-1")}}
    end
  end

  defmodule AfterOnly do
    def after_tool_call(tool_call, result, context) do
      send(context.test_pid, {:after_tool_call, tool_call, result})
      {:ok, {:ok, %{result: :transformed}, []}}
    end
  end

  defmodule NameChanging do
    def before_tool_call(tool_call, _context), do: {:ok, %{tool_call | name: "other"}}
  end

  defmodule ModuleChanging do
    def before_tool_call(tool_call, _context), do: {:ok, %{tool_call | action_module: BeforeOnly}}
  end

  test "missing callbacks use identity behavior" do
    tool_call = %{id: "call-1", name: "search", arguments: %{"query" => "hello"}, action_module: SearchAction}
    result = {:ok, %{result: "hello"}, []}

    assert {:ok, ^tool_call} = ToolInterceptor.before_tool_call(NoCallbacks, tool_call, %{})
    assert {:ok, ^result} = ToolInterceptor.after_tool_call(NoCallbacks, tool_call, result, %{})
  end

  test "before_tool_call can transform arguments without requiring after_tool_call" do
    tool_call = %{id: "call-1", name: "search", arguments: %{"query" => "hello"}, action_module: SearchAction}

    assert {:ok, transformed} = ToolInterceptor.before_tool_call(BeforeOnly, tool_call, %{test_pid: self()})
    assert transformed.arguments == %{"query" => "hello", "tenant_id" => "tenant-1"}
    assert_receive {:before_tool_call, ^tool_call}

    result = {:ok, %{result: "hello"}, []}
    assert {:ok, ^result} = ToolInterceptor.after_tool_call(BeforeOnly, transformed, result, %{})
  end

  test "after_tool_call can transform canonical result without requiring before_tool_call" do
    tool_call = %{id: "call-1", name: "search", arguments: %{}, action_module: SearchAction}
    result = {:ok, %{result: "hello"}, []}

    assert {:ok, ^tool_call} = ToolInterceptor.before_tool_call(AfterOnly, tool_call, %{})

    assert {:ok, {:ok, %{result: :transformed}, []}} =
             ToolInterceptor.after_tool_call(AfterOnly, tool_call, result, %{test_pid: self()})

    assert_receive {:after_tool_call, ^tool_call, ^result}
  end

  test "before_tool_call rejects tool name changes" do
    tool_call = %{id: "call-1", name: "search", arguments: %{}, action_module: SearchAction}

    assert {:error, {:tool_interceptor_changed_name, NameChanging, "search", "other"}} =
             ToolInterceptor.before_tool_call(NameChanging, tool_call, %{})
  end

  test "before_tool_call rejects action module changes" do
    tool_call = %{id: "call-1", name: "search", arguments: %{}, action_module: SearchAction}

    assert {:error, {:tool_interceptor_changed_action_module, ModuleChanging, SearchAction, BeforeOnly}} =
             ToolInterceptor.before_tool_call(ModuleChanging, tool_call, %{})
  end
end
