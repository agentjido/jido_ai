defmodule JidoAI.Examples.ToolResults.Directory do
  @moduledoc "Reads an actual test-owned directory."
  use Jido.Action, name: "inspect_directory", schema: Zoi.object(%{path: Zoi.string()})

  def run(%{path: path}, context) do
    send(context.observer, {:directory_read, path, context})

    case File.ls(path) do
      {:ok, names} ->
        {:ok, Jido.Action.Output.raw(Enum.sort(names))}

      {:error, reason} ->
        {:error,
         Jido.Action.Error.execution_error("Directory read failed", %{
           path: path,
           reason: reason,
           retry: false
         })}
    end
  end
end

defmodule JidoAI.Examples.ToolResults.FlowFailure do
  @moduledoc "Returns a Flow-owned error from an actual Flow step."
  use Jido.Action, name: "fixture_flow_failure", schema: Zoi.object(%{n: Zoi.integer()})

  def run(%{n: n}, _),
    do:
      {:error,
       Jido.Flow.Error.execution_error("Fixture Flow failure", %{
         value: n,
         reason: :unavailable,
         retry: false
       })}
end

defmodule JidoAI.Examples.ToolResults.BrokenFlow do
  @moduledoc "A callable Flow retains its error type and cause."
  use Jido.Flow, name: "fixture_broken_flow", schema: Zoi.object(%{n: Zoi.integer()})

  flow do
    step "fail", action: JidoAI.Examples.ToolResults.FlowFailure, params: input()
    output result("fail")
  end
end

defmodule JidoAI.Examples.ToolResults.NativeAgent do
  @moduledoc "The native DSL runs parallel tools and a nested Flow through one owner."
  use Jido.Agent, name: "native_tool_results", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      models do
        model(:answer, :example)
      end

      reasoning :react do
        model(:answer)
        tool_concurrency(2)
      end

      tools do
        action JidoAI.Examples.AIRuntime.WaitTool, as: :wait, forward_context: [:observer]
        flow(JidoAI.Examples.ToolResults.BrokenFlow, as: :broken_flow)
      end

      requests do
        mode(:session)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end

defmodule JidoAI.Examples.ToolResults.Value do
  @moduledoc "Returns each supported result form through a real core Action."
  use Jido.Action, name: "fixture_value", schema: Zoi.object(%{kind: Zoi.string()})

  def run(%{kind: kind}, context) do
    send(context.observer, {:value_called, kind})

    case kind do
      "text" ->
        {:ok, Jido.Action.Output.raw("Tool text")}

      "number" ->
        {:ok, Jido.Action.Output.raw(7)}

      "map" ->
        {:ok, %{value: 7}}

      "triple" ->
        {:ok, %{value: 8}, []}

      "unsafe" ->
        {:ok,
         Jido.Action.Output.raw(%{
           owner: self(),
           ref: make_ref(),
           nested: %{secret_key: "fixture-secret"}
         })}

      "parts" ->
        {:ok,
         Jido.Action.Output.raw(%ReqLLM.ToolResult{
           output: %{read: true},
           content: [ReqLLM.Message.ContentPart.text("Tool part")]
         })}

      "file_result" ->
        {:ok,
         Jido.Action.Output.raw(%ReqLLM.ToolResult{output: %{read: true}, content: [file()]})}

      "file_map" ->
        {:ok, %{read: true, __content_parts__: [file()]}}

      "file_list" ->
        {:ok, Jido.Action.Output.raw([file()])}

      "pdf" ->
        {:ok,
         Jido.Action.Output.raw(%ReqLLM.ToolResult{
           output: %{read: true},
           content: [
             ReqLLM.Message.ContentPart.file(
               <<0xE2, 0x28, 0xA1>>,
               "fixture.pdf",
               "application/pdf"
             )
           ]
         })}

      "file_reference" ->
        {:ok,
         Jido.Action.Output.raw([
           %{
             "type" => "file_id",
             "file_id" => "file_notes",
             "media_type" => "text/plain",
             "filename" => "notes.txt",
             "metadata" => %{"label" => "fixture"}
           }
         ])}

      "invalid" ->
        :invalid

      "raise" ->
        raise ArgumentError, "Fixture tool exception"
    end
  end

  defp file,
    do: ReqLLM.Message.ContentPart.file(<<0xE2, 0x28, 0xA1>>, "fixture.png", "image/png")
end

defmodule JidoAI.Examples.ToolResults.Agent do
  @moduledoc "Real tool outputs drive the next model call and request inspection."
  use Jido.AI.Agent,
    name: "tool_results_agent",
    model: :example,
    streaming: false,
    tools: [JidoAI.Examples.ToolResults.Directory, JidoAI.Examples.ToolResults.Value]
end
