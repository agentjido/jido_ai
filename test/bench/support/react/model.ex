defmodule JidoAI.Bench.ReAct.Model do
  @moduledoc false

  def start!(tool_rounds, round_counter) when is_integer(tool_rounds) and tool_rounds > 0 do
    script = List.duplicate({:tool, "echo"}, tool_rounds) ++ [{:text, "done"}]

    {:ok, pid} =
      Agent.start_link(fn ->
        %{script: script, calls: 0}
      end)

    Req.Test.stub(__MODULE__, fn conn ->
      {reply, call_number} =
        Agent.get_and_update(pid, fn %{script: [next | rest]} = state ->
          call_number = state.calls + 1

          {{next, call_number}, %{state | script: rest, calls: call_number}}
        end)

      :atomics.put(round_counter, 1, min(call_number, tool_rounds))
      Req.Test.json(conn, response(output(reply)))
    end)

    pid
  end

  def summary(pid) do
    Agent.get(pid, fn state ->
      %{
        calls: state.calls,
        replies_left: length(state.script)
      }
    end)
  end

  def stop(pid) when is_pid(pid), do: Agent.stop(pid)

  defp output({:text, text}) do
    [
      %{
        "type" => "message",
        "id" => "msg-#{System.unique_integer([:positive])}",
        "role" => "assistant",
        "status" => "completed",
        "content" => [%{"type" => "output_text", "text" => text, "annotations" => []}]
      }
    ]
  end

  defp output({:tool, name}) do
    id = System.unique_integer([:positive])

    [
      %{
        "type" => "function_call",
        "id" => "fc-#{id}",
        "call_id" => "call-#{id}",
        "name" => name,
        "arguments" => "{}",
        "status" => "completed"
      }
    ]
  end

  defp response(output) do
    %{
      "id" => "resp-#{System.unique_integer([:positive])}",
      "object" => "response",
      "created_at" => 1,
      "model" => "gpt-4o-mini",
      "status" => "completed",
      "error" => nil,
      "incomplete_details" => nil,
      "parallel_tool_calls" => true,
      "output" => output,
      "usage" => %{
        "input_tokens" => 20,
        "input_tokens_details" => %{"cached_tokens" => 0},
        "output_tokens" => 6,
        "output_tokens_details" => %{"reasoning_tokens" => 0},
        "total_tokens" => 26
      }
    }
  end
end
