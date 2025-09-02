# Chain of Thought Demo with LLM Integration
#
# This script demonstrates the Chain of Thought pattern using Jido agents
# with action chaining via EnqueueAction directives and LLM-powered reasoning.
# To run: `mix run examples/chain_of_thought_demo.exs`
#
# Note: Requires API keys to be set for LLM calls (e.g., OPENAI_API_KEY)

# Load the actions first
Code.require_file("chain_of_thought_action.exs", __DIR__)

defmodule ChainOfThoughtDemo do
  @moduledoc """
  Interactive demo showing Chain of Thought pattern with Jido agents and LLM integration.
  Uses Jido.AI.generate_text for dynamic reasoning and analysis at each step.
  """

  def run do
    IO.puts("=== Chain of Thought Demo ===\n")

    # Start a Jido AI agent
    IO.puts("1. Starting Jido AI Agent...")
    {:ok, pid} = Jido.AI.Agent.start_link(
      id: "cot_demo_agent",
      actions: [
        ChainOfThoughtAction,
        AnalyzeProblemAction, 
        ExecuteStepAction,
        SummarizeSolutionAction
      ]
    )

    IO.puts("   ✓ Agent started with PID: #{inspect(pid)}")
    IO.puts("   ✓ Registered actions: ChainOfThought, AnalyzeProblem, ExecuteStep, SummarizeSolution")
    IO.puts("   ✓ LLM Integration: Each action uses Jido.AI.generate_text for intelligent reasoning")

    # Demo the chain of thought process
    IO.puts("\n2. Chain of Thought Problem Solving with LLM:")
    demo_chain_of_thought(pid)

    # Demo with different parameters
    IO.puts("\n3. Chain of Thought with Custom Parameters:")
    demo_custom_chain(pid)

    # Demo monitoring the chain execution
    IO.puts("\n4. Monitoring Chain Execution:")
    demo_monitor_chain(pid)

    IO.puts("\n=== Demo Complete ===")

    # Clean up
    GenServer.stop(pid, :normal)
    IO.puts("Agent stopped.")
  end

  defp demo_chain_of_thought(pid) do
    problem = "How to optimize database query performance in a web application"
    
    IO.puts("   • Starting Chain of Thought for problem:")
    IO.puts("     Problem: #{problem}")
    IO.puts("     Command: Jido.send_signal(pid, \"instruction\", %{action: \"chain_of_thought\", params: %{problem: problem}})")

    case Jido.Agent.Interaction.send_signal(pid, "instruction", %{action: "chain_of_thought", params: %{problem: problem}}) do
      {:ok, signal_id} ->
        IO.puts("     ✓ Chain initiated successfully!")
        IO.puts("       Signal ID: #{signal_id}")
        IO.puts("       Chain of Thought action has been enqueued")
        
        # Give the chain time to execute
        Process.sleep(100)
        
        # Check agent state to see what happened
        case Jido.get_agent_state(pid) do
          {:ok, state} -> IO.puts("     ✓ Agent state retrieved: #{inspect(Map.keys(state))}")
          {:error, reason} -> IO.puts("     ✗ Error getting state: #{inspect(reason)}")
        end
        
      {:error, reason} ->
        IO.puts("     ✗ Error: #{inspect(reason)}")
    end
  end

  defp demo_custom_chain(pid) do
    problem = "Design a microservices architecture for a social media platform"
    
    IO.puts("   • Chain of Thought with custom parameters:")
    IO.puts("     Problem: #{problem}")
    IO.puts("     Max Steps: 5")
    IO.puts("     Context Key: custom_session")

    params = %{
      problem: problem,
      max_steps: 5,
      context_key: "custom_session"
    }

    case Jido.Agent.Interaction.send_signal(pid, "instruction", %{action: "chain_of_thought", params: params}) do
      {:ok, signal_id} ->
        IO.puts("     ✓ Custom chain initiated!")
        IO.puts("       Signal ID: #{signal_id}")
        IO.puts("       Custom chain parameters applied")
        
        # Let it run a bit
        Process.sleep(50)
        
      {:error, reason} ->
        IO.puts("     ✗ Error: #{inspect(reason)}")
    end
  end

  defp demo_monitor_chain(pid) do
    problem = "Create a disaster recovery plan for cloud infrastructure"
    
    IO.puts("   • Monitoring chain execution in real-time:")
    IO.puts("     Problem: #{problem}")

    # Start the chain
    case Jido.Agent.Interaction.send_signal(pid, "instruction", %{action: "chain_of_thought", params: %{problem: problem, max_steps: 3}}) do
      {:ok, signal_id} ->
        IO.puts("     ✓ Chain started with signal: #{signal_id}")
        
        # Monitor execution by checking agent state periodically
        monitor_execution(pid, signal_id, 5)
        
      {:error, reason} ->
        IO.puts("     ✗ Error starting chain: #{inspect(reason)}")
    end
  end

  defp monitor_execution(pid, signal_id, max_checks) do
    monitor_execution(pid, signal_id, max_checks, 0)
  end

  defp monitor_execution(_pid, _signal_id, max_checks, current_check) when current_check >= max_checks do
    IO.puts("     ✓ Monitoring complete (reached max checks)")
  end

  defp monitor_execution(pid, signal_id, max_checks, current_check) do
    Process.sleep(100)  # Wait a bit between checks
    
    case Jido.get_agent_state(pid) do
      {:ok, state} -> 
        IO.puts("     🔍 Agent state keys: #{inspect(Map.keys(state))}")
      {:error, reason} -> 
        IO.puts("     🔍 Error getting state: #{inspect(reason)}")
    end
    
    IO.puts("     📊 Check #{current_check + 1}: Monitoring agent state")
    
    # For now, just show we're monitoring - actual state structure may vary
    # In a real implementation, you'd filter the state for session results
    
    # Continue monitoring if we haven't reached max
    if current_check < max_checks - 1 do
      monitor_execution(pid, signal_id, max_checks, current_check + 1)
    else
      IO.puts("     ✓ Monitoring complete (reached max checks)")
    end
  end
end

# Run the demo if this file is executed directly
if Path.basename(__ENV__.file) == "chain_of_thought_demo.exs" do
  ChainOfThoughtDemo.run()
end
