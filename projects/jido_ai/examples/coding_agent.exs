require Logger

defmodule CodingDemo do
  use Jido, otp_app: :jido_ai
  require Logger

  # Skill that bundles all coding-related actions
  defmodule CodingToolsSkill do
    use Jido.Skill,
      name: "coding_tools",
      description: "File I/O and code execution helpers for coding agent",
      category: "developer_tools",
      tags: ["file", "code", "exec"],
      vsn: "0.1.0",
      opts_key: :coding_tools,
      # Just list existing actions - no custom implementation!
      actions: [
        Jido.Tools.Files.ReadFile,
        Jido.Tools.Files.WriteFile,
        Jido.Tools.Files.DeleteFile,
        Jido.Tools.Files.MakeDirectory,
        Jido.Tools.Files.ListDirectory,
        JidoAI.Actions.RunCode
      ]
  end

  # Single iteration action that handles one LLM conversation turn
  defmodule Actions.CodingIteration do
    use Jido.Action,
      name: "coding_iteration",
      description: "Runs one LLM conversation turn and decides whether to continue",
      schema: [
        messages: [type: :any, required: true, doc: "List of Message structs"],
        iteration: [type: :non_neg_integer, default: 0],
        max_iterations: [type: :pos_integer, default: 10],
        continue: [type: :boolean, default: true]
      ],
      output_schema: [
        iteration: [type: :pos_integer, required: true],
        continue: [type: :boolean, required: true],
        final: [type: :boolean, default: false]
      ]

    require Logger
    @coding_skill CodingDemo.CodingToolsSkill

    @impl true
    def run(params, ctx) do
      Logger.info("🔄 CodingIteration.run CALLED WITH PARAMS: #{inspect(params, pretty: true)}")
      Logger.info("🔍 CodingIteration context keys: #{inspect(Map.keys(ctx))}")

      # Pattern match after logging
      %{messages: messages, iteration: iteration, continue: continue, max_iterations: max_iterations} = params

      cond do
        continue == false ->
          Logger.info("🛑 CodingIteration: Continue is false, stopping at iteration #{iteration}")
          {:ok, %{iteration: iteration, continue: false, final: true}}

        iteration >= max_iterations ->
          Logger.info("🛑 CodingIteration: Max iterations (#{max_iterations}) reached at iteration #{iteration}, stopping")
          {:ok, %{iteration: iteration, continue: false, final: true}}

        true ->
          Logger.info("🚀 CodingIteration #{iteration + 1}/#{max_iterations} starting...")
          Logger.info("🔍 CodingIteration messages count: #{length(messages)}")

          case Jido.AI.generate_text("openai:gpt-4o-mini", messages,
          actions: CodingDemo.CodingToolsSkill.actions(),
          temperature: 0.1) do
          {:ok, text} ->
          Logger.info("✅ LLM Response: #{String.slice(text, 0, 100)}#{if String.length(text) > 100, do: "...", else: ""}")

          # Add assistant message
          new_messages = messages ++ [Jido.AI.Message.new(:assistant, text)]

          # Check for completion
          continue? = not String.contains?(text, "TASK_COMPLETE")

          if continue? do
            Logger.info("🔄 Continuing to next iteration...")
          else
            Logger.info("🎉 Task completed! Found TASK_COMPLETE in response")
          end

          # Update parameters for next iteration
          new_params = %{
            messages: new_messages,
            continue: continue?,
           iteration: iteration + 1,
           max_iterations: max_iterations
          }

          result_meta = %{
          iteration: iteration + 1,
          continue: continue?,
            next_params: new_params
          }

          {:ok, result_meta, %{next_params: new_params}}

            {:error, reason} ->
              Logger.error("❌ LLM call failed: #{inspect(reason)}")
              {:error, reason}
          end
      end
    end

    defp execute_tool_calls([], messages, _ctx), do: {messages, []}
    defp execute_tool_calls(tool_calls, messages, ctx) do
      Logger.info("🔧 Executing #{length(tool_calls)} tool calls")

      {new_messages, results} =
        Enum.reduce(tool_calls, {messages, []}, fn tool_call, {acc_messages, acc_results} ->
          %{name: name, arguments: args} = tool_call
          Logger.info("🛠️  Executing tool: #{name}")

          case @coding_skill.execute_tool(name, args, ctx) do
            {:ok, result} ->
              Logger.info("✅ Tool #{name} succeeded: #{inspect(result)}")
              tool_call_id = Map.get(tool_call, :id, "unknown")
              tool_result_msg = Jido.AI.Message.tool_result(tool_call_id, name, result)
              {acc_messages ++ [tool_result_msg], acc_results ++ [result]}

            {:error, error} ->
              Logger.error("❌ Tool #{name} failed: #{inspect(error)}")
              tool_call_id = Map.get(tool_call, :id, "unknown")
              tool_result_msg = Jido.AI.Message.tool_result(tool_call_id, name, {:error, error})
              {acc_messages ++ [tool_result_msg], acc_results ++ [{:error, error}]}
          end
        end)

      {new_messages, results}
    end
  end

  # Action to start the coding task
  defmodule Actions.RunTask do
    use Jido.Action,
      name: "run_task",
      description: "Starts a coding task with While loop execution",
      schema: [
        task: [type: :string, required: true]
      ]

    @impl true
    def run(%{task: task}, ctx) do
      Logger.info("🚀 RunTask.run CALLED!")
      Logger.info("🔍 RunTask task: #{task}")
      Logger.info("🔍 RunTask context keys: #{inspect(Map.keys(ctx))}")

      # Build the system prompt
      system_prompt = build_system_prompt(task)
      initial_messages = [Jido.AI.Message.new(:user, system_prompt)]
      Logger.info("🔍 RunTask created #{length(initial_messages)} initial messages")

      # Create the While loop instruction - body params go directly in params
      while_instruction = %Jido.Instruction{
        action: Jido.Actions.While,
        params: %{
          body: CodingDemo.Actions.CodingIteration,
          params: %{
            messages: initial_messages,
            iteration: 0,
            max_iterations: 10,
            continue: true
          },
          condition_field: :continue,
          max_iterations: 10
        }
      }

      Logger.info("🔄 RunTask: Creating While loop instruction")
      Logger.info("🔍 RunTask: While instruction action: #{inspect(while_instruction.action)}")
      Logger.info("🔍 RunTask: While instruction body: #{inspect(while_instruction.params.body)}")
      Logger.info("🔍 RunTask: While instruction condition_field: #{inspect(while_instruction.params.condition_field)}")
      Logger.info("🔍 RunTask: While instruction nested params keys: #{inspect(Map.keys(while_instruction.params.params))}")

      enqueue_directive = Jido.Agent.Directive.Enqueue.new(while_instruction)
      Logger.info("🔍 RunTask: Created enqueue directive: #{inspect(enqueue_directive)}")

      Logger.info("🔄 RunTask: Returning with enqueue directive")
      {:ok, "Task started", [enqueue_directive]}
    end

    defp build_system_prompt(task) do
      """
      You are a coding assistant. Your task is: #{task}

      You have access to file operations and code execution tools:
      - read_file: Read contents of a file
      - write_file: Write content to a file
      - delete_file: Delete a file
      - make_directory: Create a directory
      - list_directory: List directory contents
      - run_code: Execute code (supports multiple languages)

      Work step by step:
      1. Understand the task
      2. Use file operations to read/write/create files as needed
      3. Use run_code to execute and test your solutions
      4. Verify your work
      5. When you complete the task successfully, respond with "TASK_COMPLETE" in your message.

      Be methodical and explain your reasoning at each step.
      """
    end
  end

  # Ultra-simplified agent implementation
  defmodule Agent do
    use Jido.Agent,
      name: "coding_agent",
      actions: [
        CodingDemo.Actions.RunTask,
        CodingDemo.Actions.CodingIteration,
        Jido.Actions.While
      ]
  end

  def demo do
    task = "Create a simple Elixir script that reads a JSON file called 'data.json', counts the number of objects in it, and writes the count to a file called 'count.txt'"

    Logger.info("🚀 DEMO STARTING...")

    {:ok, pid} = Jido.Agent.Server.start_link(
      log_level: :debug,
      agent: CodingDemo.Agent,
      routes: [
        {"run_task", %Jido.Instruction{action: CodingDemo.Actions.RunTask}}
      ]
    )
    Logger.info("🔍 DEMO: Agent server started with PID: #{inspect(pid)}")

    # Create some test data first
    test_data = %{
      "users" => [
        %{"name" => "Alice", "age" => 30},
        %{"name" => "Bob", "age" => 25},
        %{"name" => "Charlie", "age" => 35}
      ],
      "products" => [
        %{"id" => 1, "name" => "Widget"},
        %{"id" => 2, "name" => "Gadget"}
      ]
    }

    if File.exists?("count.txt"), do: File.rm!("count.txt")
    File.write!("data.json", Jason.encode!(test_data, pretty: true))

    case Jido.Agent.Server.call(pid, Jido.Signal.new!("run_task", %{task: task})) do
      {:ok, result} ->
        Logger.info("📊 DEMO: Agent call result: #{inspect(result)}")

        # Wait a bit for async processing
        Logger.info("🔍 DEMO: Waiting 15 seconds for async processing...")
        Process.sleep(15000)

        # Show the results
        if File.exists?("count.txt") do
          count = File.read!("count.txt")
          Logger.info("📄 DEMO: count.txt contains: #{count}")
        else
          Logger.warning("⚠️  DEMO: count.txt was not created")
        end

      {:error, reason} ->
        Logger.error("❌ DEMO: Agent call failed: #{inspect(reason)}")
    end

    # Cleanup
    Process.exit(pid, :normal)
  end

  def llm_demo do
    {:ok, response} = Jido.AI.generate_text("openai:gpt-4o-mini", "What is the capital of France?")
    Logger.info("🔍 LLM DEMO: Response: #{inspect(response)}")
  end
end

# Set up logging
Logger.configure(level: :debug)

# Run the demo if this file is executed directly
if Path.basename(__ENV__.file) == "coding_agent.exs" do
  CodingDemo.demo()
end
