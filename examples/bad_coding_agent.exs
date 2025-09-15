defmodule CodingDemo do
  use Jido, otp_app: :jido_ai

  require Logger

  defmodule CodingAgent do
    @moduledoc """
    A simple coding agent that can read/write files and execute code.
    Ported from TypeScript implementation using Jido framework.
    """

    use Jido.Agent,
      name: "coding_agent"

    alias Jido.AI

    @doc """
    Run the coding agent with a given task.
    """
    def run_task(task, max_iterations \\ 10) do
      Logger.info("🚀 Starting coding agent with task: #{task}")

      messages = [
        %AI.Message{
          role: :user,
          content: """
          You are a coding agent. Complete this task: #{task}

          You can use these tools:
          - read_file: to examine existing files  
          - write_file: to create/modify files
          - run_code: to test/execute code

          Work step by step. When you're completely done, end your response with "TASK_COMPLETE".
          """
        }
      ]

      loop(messages, 1, max_iterations)
    end

    defp loop(messages, iteration, max_iterations) when iteration <= max_iterations do
      Logger.info("--- Iteration #{iteration} ---")

      # Get all available tools from the agent
      tools = get_tools()

      # Generate response with tool calling capability
      case AI.generate_text(
             "openai:gpt-4o-mini",
             messages,
             tools: tools,
             temperature: 0.1
           ) do
        {:ok, text} ->
          Logger.info("🤖 Agent response: #{text}")

          # Add the assistant's response to conversation
          assistant_message = %AI.Message{role: :assistant, content: text}
          updated_messages = messages ++ [assistant_message]

          # Check if task is complete
          if String.contains?(text, "TASK_COMPLETE") do
            Logger.info("✅ Task completed!")
            {:ok, updated_messages}
          else
            # For now, just prompt to continue (tool calling will be added later)
            Logger.info("🤔 Adding prompt to continue...")
            continue_message = %AI.Message{
              role: :user, 
              content: "Continue with the next step or call TASK_COMPLETE if done."
            }
            loop(updated_messages ++ [continue_message], iteration + 1, max_iterations)
          end

        {:error, reason} ->
          Logger.error("❌ Error generating text: #{inspect(reason)}")
          {:error, reason}
      end
    end

    defp loop(_messages, _iteration, max_iterations) do
      Logger.warning("⚠️ Reached maximum iterations (#{max_iterations})")
      {:error, :max_iterations_reached}
    end

    # Tool execution functions (commented out for now - will implement when tool calling works)
    # defp execute_tools(tool_calls, messages) do
    #   # Implementation here
    # end

    defp get_tools do
      [
        %{
          type: "function",
          function: %{
            name: "read_file",
            description: "Read content from a file",
            parameters: %{
              type: "object",
              properties: %{
                path: %{type: "string", description: "Path to the file to read"}
              },
              required: ["path"]
            }
          }
        },
        %{
          type: "function",
          function: %{
            name: "write_file",
            description: "Write content to a file",
            parameters: %{
              type: "object",
              properties: %{
                path: %{type: "string", description: "Path to the file to write"},
                content: %{type: "string", description: "Content to write to the file"}
              },
              required: ["path", "content"]
            }
          }
        },
        %{
          type: "function",
          function: %{
            name: "run_code",
            description: "Execute code and return the result",
            parameters: %{
              type: "object",
              properties: %{
                code: %{type: "string", description: "The code to execute"},
                language: %{type: "string", description: "The programming language"}
              },
              required: ["code", "language"]
            }
          }
        }
      ]
    end
  end

  def demo do
    task = "Create a simple Elixir script that reads a JSON file called 'data.json', counts the number of objects in it, and writes the count to a file called 'count.txt'"

    Logger.info("🚀 Starting coding agent demo...")
    
    # Start the agent with skills
    {:ok, _agent_pid} = CodingAgent.start_link(
      skills: [
        Jido.Skills.Files,
        JidoAI.Skills.Exec
      ]
    )
    
    case CodingAgent.run_task(task) do
      {:ok, conversation} ->
        Logger.info("✅ Demo completed successfully!")
        Logger.info("Final conversation length: #{length(conversation)} messages")
        
      {:error, reason} ->
        Logger.error("❌ Demo failed: #{inspect(reason)}")
    end
  end
end

# Set up logging
Logger.configure(level: :debug)

# Run the demo if this file is executed directly
if Path.basename(__ENV__.file) == "coding_agent.exs" do
  CodingDemo.demo()
end
