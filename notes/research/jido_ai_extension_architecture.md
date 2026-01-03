# Jido AI Extension Architecture

## Overview

This document outlines the architecture for extending Jido v2 with AI and Large Language Model (LLM) capabilities. The extension will provide a comprehensive framework for implementing various AI algorithms such as ReAct, Chain-of-Thought, Tree-of-Thoughts, Graph-of-Thoughts, GEPA, and TRM, while maintaining the core principles of Jido's immutable agent architecture and strategy-based execution.

## Architecture Design

### Core Components

#### 1. Jido.AI Module Structure

```elixir
lib/jido_ai/
├── application.ex          # Main application supervisor
├── jido_ai.ex              # Main module
├── config/
│   └── config.ex           # Configuration management
├── strategies/
│   ├── react.ex            # ReAct strategy implementation
│   ├── chain_of_thought.ex # Chain-of-Thought strategy
│   ├── tree_of_thoughts.ex # Tree-of-Thoughts strategy
│   ├── graph_of_thoughts.ex # Graph-of-Thoughts strategy
│   ├── gepa.ex             # GEPA strategy
│   └── trm.ex              # TRM strategy
├── algorithms/
│   ├── algorithm.ex        # Algorithm behavior definition
│   ├── base.ex             # Base algorithm implementation
│   ├── sequential.ex       # Sequential execution algorithm
│   ├── parallel.ex         # Parallel execution algorithm
│   ├── hybrid.ex           # Hybrid execution algorithm
│   └── composite.ex        # Composite algorithm (combines others)
├── skills/
│   ├── llm_skill.ex        # LLM interaction skill
│   ├── reasoning_skill.ex  # Reasoning capabilities
│   ├── planning_skill.ex   # Planning capabilities
│   └── subagent_skill.ex   # Sub-agent management
├── actions/
│   ├── llm_actions.ex      # LLM-related actions
│   ├── reasoning_actions.ex # Reasoning actions
│   └── planning_actions.ex # Planning actions
├── models/
│   ├── model.ex            # Model behavior
│   ├── openai.ex           # OpenAI integration
│   ├── anthropic.ex        # Anthropic integration
│   └── local.ex            # Local model integration
├── prompts/
│   ├── prompt.ex           # Prompt management
│   ├── templates.ex        # Prompt templates
│   └── library.ex          # Prompt library
├── memory/
│   ├── memory.ex           # Memory management
│   ├── context.ex          # Context management
│   └── storage.ex          # Storage backends
├── tools/
│   ├── tool.ex             # Tool behavior
│   ├── registry.ex         # Tool registry
│   └── executor.ex         # Tool execution
├── agents/
│   ├── ai_agent.ex         # AI-capable agent
│   ├── subagent.ex         # Sub-agent implementation
│   └── coordinator.ex      # Agent coordination
└── telemetry/
    └── telemetry.ex        # AI-specific telemetry
```

#### 2. Strategy Implementations

Each AI algorithm will be implemented as a Jido strategy, leveraging the existing strategy protocol:

```elixir
defmodule Jido.AI.Strategies.ReAct do
  @moduledoc """
  ReAct (Reasoning + Acting) strategy for LLM integration.

  This strategy implements the ReAct pattern where the agent:
  1. Reasons about the current situation
  2. Decides on an action to take
  3. Observes the result
  4. Repeats until completion
  """

  use Jido.Agent.Strategy

  alias Jido.AI.Models.Model
  alias Jido.AI.Prompts.Prompt
  alias Jido.AI.Tools.Tool

  @impl true
  def cmd(agent, instructions, context) do
    # ReAct implementation
    {updated_agent, directives} = process_react_loop(agent, instructions, context)
    {updated_agent, directives}
  end

  @impl true
  def init(agent, context) do
    # Initialize ReAct-specific state
    initial_state = %{
      reasoning_steps: [],
      action_history: [],
      current_thought: nil,
      max_iterations: context[:strategy_opts][:max_iterations] || 10
    }

    strategy_state = put_in(agent.state[:__strategy__], initial_state)
    {%{agent | state: strategy_state}, []}
  end

  defp process_react_loop(agent, instructions, context) do
    # Main ReAct loop implementation
  end
end
```

#### 3. Algorithm Base Architecture

```elixir
defmodule Jido.AI.Algorithms.Base do
  @moduledoc """
  Base algorithm implementation that all AI algorithms extend.
  """

  alias Jido.AI.Algorithms.Algorithm

  @callback execute(input :: map(), context :: map()) ::
              {:ok, result :: map()} | {:error, reason :: term()}

  @callback can_execute?(input :: map(), context :: map()) :: boolean()

  @callback metadata() :: map()

  defmacro __using__(opts) do
    quote do
      @behaviour Jido.AI.Algorithms.Algorithm

      def metadata, do: unquote(opts)

      defoverridable metadata: 0
    end
  end
end

defmodule Jido.AI.Algorithms.Sequential do
  @moduledoc """
  Sequential algorithm execution - runs algorithms one after another.
  """

  use Jido.AI.Algorithms.Base,
    name: "sequential",
    description: "Execute algorithms sequentially"

  @impl true
  def execute(input, context) do
    algorithms = context[:algorithms] || []

    Enum.reduce_while(algorithms, {:ok, input}, fn algorithm, {:ok, current_input} ->
      case algorithm.execute(current_input, context) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @impl true
  def can_execute?(input, context) do
    algorithms = context[:algorithms] || []
    Enum.all?(algorithms, & &1.can_execute?(input, context))
  end
end
```

#### 4. AI Agent Implementation

```elixir
defmodule Jido.AI.Agents.AIAgent do
  @moduledoc """
  AI-capable agent that extends Jido.Agent with AI-specific capabilities.
  """

  use Jido.Agent,
    name: "ai_agent",
    description: "AI-capable agent with LLM integration",
    schema: [
      ai_model: [type: :string, default: "gpt-4"],
      ai_config: [type: :map, default: %{}],
      reasoning_state: [type: :map, default: %{}],
      memory_context: [type: :map, default: %{}]
    ],
    strategy: Jido.AI.Strategies.ReAct,
    skills: [
      Jido.AI.Skills.LLMSkill,
      Jido.AI.Skills.ReasoningSkill,
      Jido.AI.Skills.PlanningSkill
    ]

  # AI-specific agent methods
  def think(agent, prompt) do
    # Implement AI thinking/reasoning
  end

  def plan(agent, goal) do
    # Implement AI planning
  end

  def reflect(agent, experience) do
    # Implement AI reflection/learning
  end
end
```

#### 5. Model Integration Layer

```elixir
defmodule Jido.AI.Models.Model do
  @moduledoc """
  Behavior for LLM model implementations.
  """

  @callback chat(messages :: list(), options :: keyword()) ::
              {:ok, response :: map()} | {:error, reason :: term()}

  @callback complete(prompt :: String.t(), options :: keyword()) ::
              {:ok, response :: String.t()} | {:error, reason :: term()}

  @callback embed(text :: String.t(), options :: keyword()) ::
              {:ok, embeddings :: list(float())} | {:error, reason :: term()}

  @callback capabilities() :: map()
end

defmodule Jido.AI.Models.OpenAI do
  @moduledoc """
  OpenAI API integration.
  """

  @behaviour Jido.AI.Models.Model

  @impl true
  def chat(messages, options) do
    # OpenAI chat completion implementation
  end

  @impl true
  def complete(prompt, options) do
    # OpenAI completion implementation
  end

  @impl true
  def embed(text, options) do
    # OpenAI embedding implementation
  end

  @impl true
  def capabilities do
    %{
      models: ["gpt-4", "gpt-3.5-turbo"],
      max_tokens: 8192,
      supports_streaming: true,
      supports_functions: true
    }
  end
end
```

#### 6. Tool System for Function Calling

```elixir
defmodule Jido.AI.Tools.Tool do
  @moduledoc """
  Behavior for AI tools that can be called by LLMs.
  """

  @callback schema() :: map()

  @callback execute(params :: map(), context :: map()) ::
              {:ok, result :: map()} | {:error, reason :: term()}

  @callback description() :: String.t()
end

defmodule Jido.AI.Tools.Registry do
  @moduledoc """
  Registry for AI tools.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register(tool_module) do
    GenServer.call(__MODULE__, {:register, tool_module})
  end

  def list_tools() do
    GenServer.call(__MODULE__, :list_tools)
  end

  def execute_tool(tool_name, params, context) do
    GenServer.call(__MODULE__, {:execute, tool_name, params, context})
  end
end
```

#### 7. Memory and Context Management

```elixir
defmodule Jido.AI.Memory.Memory do
  @moduledoc """
  Memory management for AI agents.
  """

  defstruct [
    :short_term,
    :long_term,
    :episodic,
    :semantic,
    :working
  ]

  def new() do
    %__MODULE__{
      short_term: [],
      long_term: [],
      episodic: [],
      semantic: %{},
      working: %{}
    }
  end

  def add_short_term(memory, item) do
    %{memory | short_term: [item | memory.short_term]}
  end

  def consolidate(memory) do
    # Consolidate short-term to long-term memory
  end
end

defmodule Jido.AI.Memory.Context do
  @moduledoc """
  Context management for AI agents.
  """

  defstruct [
    :conversation_history,
    :current_task,
    :relevant_memories,
    :tool_results,
    :subagent_states
  ]

  def new() do
    %__MODULE__{
      conversation_history: [],
      current_task: nil,
      relevant_memories: [],
      tool_results: %{},
      subagent_states: %{}
    }
  end
end
```

## Integration with Jido v2

### 1. Strategy Integration

The AI extension will integrate seamlessly with Jido's strategy system:

```elixir
defmodule MyAIAgent do
  use Jido.Agent,
    name: "ai_agent",
    description: "AI-powered agent",
    strategy: Jido.AI.Strategies.ReAct,  # AI strategy
    skills: [
      Jido.AI.Skills.LLMSkill,
      Jido.AI.Skills.PlanningSkill
    ]
end
```

### 2. Skill Integration

AI capabilities will be provided as composable skills:

```elixir
defmodule Jido.AI.Skills.LLMSkill do
  use Jido.Skill,
    name: "llm",
    state_key: :llm,
    actions: [Jido.AI.Actions.Chat, Jido.AI.Actions.Complete],
    schema: %{
      model: [type: :string, default: "gpt-4"],
      api_key: [type: :string],
      temperature: [type: :float, default: 0.7]
    }

  @impl true
  def mount(agent, config) do
    {:ok, %{initialized: true, config: config}}
  end
end
```

### 3. Directive Extensions

New AI-specific directives will be added:

```elixir
defmodule Jido.AI.Directives.LLMCall do
  defstruct [:model, :messages, :options, :response_handler]
end

defmodule Jido.AI.Directives.SubagentSpawn do
  defstruct [:agent_module, :config, :parent_callback]
end
```

## Usage Examples

### 1. Basic AI Agent

```elixir
defmodule ChatAgent do
  use Jido.AI.Agents.AIAgent,
    name: "chat_agent",
    description: "Conversational AI agent",
    strategy: Jido.AI.Strategies.ReAct,
    skills: [
      Jido.AI.Skills.LLMSkill,
      Jido.AI.Skills.MemorySkill
    ]
end

# Usage
agent = ChatAgent.new()
{agent, _directives} = ChatAgent.cmd(agent, "Hello, how are you?")
```

### 2. Multi-Algorithm Agent

```elixir
defmodule ComplexAIAgent do
  use Jido.AI.Agents.AIAgent,
    name: "complex_ai",
    description: "AI agent using multiple algorithms",
    strategy: Jido.AI.Strategies.TreeOfThoughts,
    skills: [
      Jido.AI.Skills.LLMSkill,
      Jido.AI.Skills.PlanningSkill,
      Jido.AI.Skills.SubagentSkill
    ]
end
```

### 3. Sub-Agent Coordination

```elixir
defmodule CoordinatorAgent do
  use Jido.AI.Agents.AIAgent,
    name: "coordinator",
    description: "Coordinates multiple AI sub-agents",
    strategy: Jido.AI.Strategies.Parallel,
    skills: [
      Jido.AI.Skills.SubagentSkill
    ]

  def coordinate_task(agent, task) do
    # Spawn sub-agents for different aspects of the task
    {agent, directives} = ChatAgent.cmd(agent, [
      %Jido.AI.Directives.SubagentSpawn{
        agent_module: ResearchAgent,
        config: %{focus: :research}
      },
      %Jido.AI.Directives.SubagentSpawn{
        agent_module: AnalysisAgent,
        config: %{focus: :analysis}
      }
    ])
  end
end
```

## Advanced Features

### 1. Algorithm Composition

Algorithms can be composed and combined:

```elixir
# Create a hybrid algorithm
hybrid_algorithm = %Jido.AI.Algorithms.Hybrid{
  primary: Jido.AI.Algorithms.TreeOfThoughts,
  fallback: Jido.AI.Algorithms.ChainOfThought,
  conditions: %{
    complexity_threshold: 0.8,
    timeout_ms: 5000
  }
}
```

### 2. Adaptive Strategy Selection

```elixir
defmodule AdaptiveAIAgent do
  use Jido.AI.Agents.AIAgent,
    name: "adaptive_ai",
    description: "AI agent with adaptive strategy selection",
    strategy: {Jido.AI.Strategies.Adaptive,
      strategies: [
        {Jido.AI.Strategies.ReAct, complexity: :low},
        {Jido.AI.Strategies.TreeOfThoughts, complexity: :high},
        {Jido.AI.Strategies.GraphOfThoughts, complexity: :very_high}
      ]
    }
end
```

### 3. Multi-Modal Processing

```elixir
defmodule MultiModalAgent do
  use Jido.AI.Agents.AIAgent,
    name: "multimodal_ai",
    description: "AI agent processing multiple modalities",
    strategy: Jido.AI.Strategies.ReAct,
    skills: [
      Jido.AI.Skills.LLMSkill,
      Jido.AI.Skills.VisionSkill,
      Jido.AI.Skills.AudioSkill
    ]
end
```

## Configuration and Deployment

### 1. Configuration

```elixir
# config/config.exs
config :jido_ai,
  models: [
    openai: [
      api_key: System.get_env("OPENAI_API_KEY"),
      default_model: "gpt-4"
    ],
    anthropic: [
      api_key: System.get_env("ANTHROPIC_API_KEY"),
      default_model: "claude-3-opus"
    ]
  ],
  memory: [
    storage_backend: Jido.AI.Memory.Storage.Ecto,
    consolidation_interval: :timer.minutes(5)
  ],
  telemetry: [
    enabled: true,
    metrics: [:response_time, :token_usage, :success_rate]
  ]
```

### 2. Supervision

```elixir
defmodule MyApp.AI do
  use Application

  def start(_type, _args) do
    children = [
      Jido.AI,
      Jido.AI.Models.Registry,
      Jido.AI.Tools.Registry,
      Jido.AI.Memory.Supervisor
    ]

    opts = [strategy: :one_for_one, name: MyApp.AI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Testing and Validation

### 1. Unit Tests

```elixir
defmodule Jido.AI.Strategies.ReActTest do
  use ExUnit.Case

  alias Jido.AI.Strategies.ReAct

  test "executes ReAct strategy correctly" do
    agent = TestAgent.new()
    {agent, directives} = ReAct.cmd(agent, [%TestAction{}], %{})

    assert length(directives) > 0
    assert agent.state[:__strategy__][:reasoning_steps] != []
  end
end
```

### 2. Integration Tests

```elixir
defmodule Jido.AI.IntegrationTest do
  use ExUnit.Case

  test "AI agent completes complex task" do
    agent = ComplexAIAgent.new()
    {agent, _directives} = ComplexAIAgent.cmd(agent, "Solve this complex problem")

    assert agent.state[:task_status] == :completed
  end
end
```

## Performance Considerations

### 1. Caching

```elixir
defmodule Jido.AI.Cache do
  use GenServer

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def put(key, value, ttl \\ :timer.minutes(5)) do
    GenServer.call(__MODULE__, {:put, key, value, ttl})
  end
end
```

### 2. Rate Limiting

```elixir
defmodule Jido.AI.RateLimiter do
  use GenServer

  def check_limit(client_id) do
    GenServer.call(__MODULE__, {:check, client_id})
  end
end
```

### 3. Resource Management

```elixir
defmodule Jido.AI.ResourceManager do
  def allocate_resources(agent_id, requirements) do
    # Allocate computational resources for AI operations
  end

  def release_resources(agent_id) do
    # Release allocated resources
  end
end
```

## Monitoring and Observability

### 1. Telemetry

```elixir
defmodule Jido.AI.Telemetry do
  require Logger

  def track_llm_call(model, prompt, response, duration) do
    :telemetry.execute(
      [:jido, :ai, :llm, :call],
      %{duration: duration},
      %{model: model, prompt_length: String.length(prompt),
        response_length: String.length(response)}
    )
  end

  def track_algorithm_execution(algorithm, input, output, duration) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :execution],
      %{duration: duration},
      %{algorithm: algorithm, input_size: byte_size(input),
        output_size: byte_size(output)}
    )
  end
end
```

### 2. Metrics

```elixir
# Metrics definitions
[
  Telemetry.Metrics.counter("jido.ai.llm.call.count"),
  Telemetry.Metrics.sum("jido.ai.llm.call.duration"),
  Telemetry.Metrics.counter("jido.ai.algorithm.execution.count"),
  Telemetry.Metrics.sum("jido.ai.algorithm.execution.duration"),
  Telemetry.Metrics.counter("jido.ai.agent.subagent.spawn.count")
]
```

## Security Considerations

### 1. API Key Management

```elixir
defmodule Jido.AI.Security do
  def validate_api_key(provider, key) do
    # Validate API keys
  end

  def sanitize_input(input) do
    # Sanitize user input
  end

  def audit_log(action, user_id, details) do
    # Log security-sensitive operations
  end
end
```

### 2. Content Filtering

```elixir
defmodule Jido.AI.ContentFilter do
  def filter_content(content) do
    # Implement content filtering
  end

  def check_safety(content) do
    # Check content safety
  end
end
```

## Future Extensions

### 1. Multi-Agent Systems

```elixir
defmodule Jido.AI.MultiAgent do
  defdelegate create_swarm(agent_config, count), to: Jido.AI.Agents.Swarm
  defdelegate coordinate_agents(agent_ids, task), to: Jido.AI.Agents.Coordinator
  defdelegate merge_results(agent_results), to: Jido.AI.Agents.Merger
end
```

### 2. Learning and Adaptation

```elixir
defmodule Jido.AI.Learning do
  defdelegate learn_from_experience(agent, experience), to: Jido.AI.Learning.Reinforcement
  defdelegate adapt_strategy(agent, performance), to: Jido.AI.Learning.Adaptation
  defdelegate optimize_parameters(agent, results), to: Jido.AI.Learning.Optimization
end
```

### 3. Advanced Reasoning

```elixir
defmodule Jido.AI.Reasoning do
  defdelegate logical_reasoning(agent, premises), to: Jido.AI.Reasoning.Logical
  defdelegate causal_reasoning(agent, observations), to: Jido.AI.Reasoning.Causal
  defdelegate analogical_reasoning(agent, source, target), to: Jido.AI.Reasoning.Analogical
end
```

## Conclusion

This architecture provides a comprehensive framework for integrating AI and LLM capabilities into Jido v2 while maintaining the framework's core principles of immutability, composability, and strategy-based execution. The design allows for:

1. **Modular AI algorithms** that can be developed and tested independently
2. **Flexible strategy selection** based on task requirements
3. **Seamless integration** with existing Jido components
4. **Scalable architecture** supporting both single-agent and multi-agent scenarios
5. **Extensible design** for future AI capabilities and algorithms

The architecture leverages Jido's existing patterns for strategies, skills, and directives while adding AI-specific functionality in a clean, maintainable way. This approach ensures that the AI extension will be both powerful and easy to use for developers building AI-powered applications with Jido.

---

# Jido AI Extension Architecture with ReqLLM Integration

## Overview

This document outlines the updated architecture for extending Jido v2 with AI and Large Language Model (LLM) capabilities, leveraging [ReqLLM](https://github.com/agentjido/req_llm) as the primary LLM access layer. ReqLLM provides a unified, idiomatic Elixir interface for accessing multiple LLM providers with streaming responses and rich metadata, making it the ideal foundation for Jido's AI extension.

## Architecture Design

### Core Components

#### 1. ReqLLM Integration Layer

```
lib/jido_ai/
├── req_llm/
│   ├── adapter.ex     # ReqLLM adapter for Jido
│   ├── client.ex      # ReqLLM client wrapper
│   ├── streaming.ex   # Streaming response handling
│   ├── metadata.ex    # Metadata extraction and processing
│   └── models.ex      # Model registry integration
```

**ReqLLM Adapter Implementation:**

```elixir
defmodule Jido.AI.ReqLLM.Adapter do
  @moduledoc """
  Adapter for integrating ReqLLM with Jido AI.

  This module provides a Jido-friendly interface to ReqLLM's capabilities,
  including streaming, tool calling, and metadata handling.
  """

  alias ReqLLM.{Context, Message, Tool, StreamResponse}
  alias Jido.AI.ReqLLM.{Client, Streaming, Metadata}

  @type model_spec :: String.t() | {:atom, String.t(), keyword()} | ReqLLM.Model.t()

  # Generate text with streaming support
  def generate_text(model_spec, prompt, opts \\ []) do
    Client.generate_text(model_spec, prompt, opts)
  end

  # Stream text generation
  def stream_text(model_spec, prompt, opts \\ []) do
    Client.stream_text(model_spec, prompt, opts)
  end

  # Generate structured objects
  def generate_object(model_spec, prompt, schema, opts \\ []) do
    Client.generate_object(model_spec, prompt, schema, opts)
  end

  # Tool calling
  def call_with_tools(model_spec, prompt, tools, opts \\ []) do
    Client.call_with_tools(model_spec, prompt, tools, opts)
  end

  # Embedding generation
  def generate_embeddings(model_spec, texts, opts \\ []) do
    Client.generate_embeddings(model_spec, texts, opts)
  end

  # Metadata processing
  def process_response(response) do
    Metadata.process(response)
  end
end
```

**ReqLLM Client Implementation:**

```elixir
defmodule Jido.AI.ReqLLM.Client do
  @moduledoc """
  ReqLLM client wrapper for Jido AI.
  """

  require Logger

  alias ReqLLM.{Context, Message, Tool, StreamResponse}

  def generate_text(model_spec, prompt, opts) do
    context = build_context(prompt, opts)

    case ReqLLM.generate_text(model_spec, context, opts) do
      {:ok, response} ->
        {:ok, process_response(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def stream_text(model_spec, prompt, opts) do
    context = build_context(prompt, opts)

    case ReqLLM.stream_text(model_spec, context, opts) do
      {:ok, stream_response} ->
        {:ok, Streaming.process_stream(stream_response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def generate_object(model_spec, prompt, schema, opts) do
    context = build_context(prompt, opts)

    case ReqLLM.generate_object(model_spec, context, schema, opts) do
      {:ok, response} ->
        {:ok, process_response(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def call_with_tools(model_spec, prompt, tools, opts) do
    context = build_context(prompt, opts)
    reqllm_tools = Enum.map(tools, &convert_tool/1)

    case ReqLLM.generate_text(model_spec, context, Keyword.put(opts, :tools, reqllm_tools)) do
      {:ok, response} ->
        {:ok, process_response(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def generate_embeddings(model_spec, texts, opts) do
    case ReqLLM.Embedding.generate(model_spec, texts, opts) do
      {:ok, response} ->
        {:ok, process_response(response)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_context(prompt, opts) do
    system_message = Keyword.get(opts, :system_message)
    conversation_history = Keyword.get(opts, :conversation_history, [])

    messages =
      []
      |> maybe_add_system_message(system_message)
      |> Enum.concat(conversation_history)
      |> Enum.concat([Message.user(prompt)])

    Context.new(messages)
  end

  defp maybe_add_system_message(messages, nil), do: messages

  defp maybe_add_system_message(messages, system_message) do
    [Message.system(system_message) | messages]
  end

  defp convert_tool(tool_module) do
    # Convert Jido tool to ReqLLM tool format
    ReqLLM.tool(
      name: tool_module.name(),
      description: tool_module.description(),
      parameter_schema: tool_module.schema(),
      callback: {tool_module, :execute, [:extra, :args]}
    )
  end

  defp process_response(response) do
    %{
      content: response.content,
      usage: response.usage,
      finish_reason: response.finish_reason,
      model: response.model,
      provider: response.provider,
      metadata: extract_metadata(response)
    }
  end

  defp extract_metadata(response) do
    %{
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens,
      total_tokens: response.usage.total_tokens,
      cost: response.usage.total_cost,
      request_id: response.request_id,
      created_at: response.created_at
    }
  end
end
```

**Streaming Response Handler:**

```elixir
defmodule Jido.AI.ReqLLM.Streaming do
  @moduledoc """
  Handles streaming responses from ReqLLM.
  """

  alias ReqLLM.StreamResponse

  def process_stream(stream_response) do
    %{
      id: stream_response.id,
      tokens: StreamResponse.tokens(stream_response),
      usage: fn -> StreamResponse.usage(stream_response) end,
      finish_reason: fn -> StreamResponse.finish_reason(stream_response) end,
      metadata: fn -> extract_stream_metadata(stream_response) end
    }
  end

  defp extract_stream_metadata(stream_response) do
    %{
      model: stream_response.model,
      provider: stream_response.provider,
      request_id: stream_response.request_id,
      created_at: stream_response.created_at
    }
  end
end
```

#### 2. Updated Strategy Implementations

```elixir
defmodule Jido.AI.Strategies.ReAct do
  @moduledoc """
  ReAct (Reasoning + Acting) strategy using ReqLLM.
  """

  use Jido.Agent.Strategy

  alias Jido.AI.ReqLLM.Adapter
  alias Jido.AI.Tools.Registry

  @impl true
  def cmd(agent, instructions, context) do
    model_spec = agent.state[:ai_config][:model] || "anthropic:claude-haiku-4-5"
    tools = Registry.list_tools()

    # Extract prompt from instructions
    prompt = extract_prompt(instructions)

    # Execute ReAct loop with streaming
    case Adapter.stream_text(model_spec, prompt,
           tools: tools,
           system_message: build_system_message(agent),
           conversation_history: get_conversation_history(agent)) do
      {:ok, stream_response} ->
        process_streaming_response(agent, stream_response, context)

      {:error, reason} ->
        {agent, [%Jido.Agent.Directive.Error{error: reason}]}
    end
  end

  defp extract_prompt(instructions) do
    # Extract prompt from Jido instructions
    instructions
    |> List.first()
    |> case do
      %{prompt: prompt} -> prompt
      %{text: text} -> text
      string when is_binary(string) -> string
      _ -> "No prompt provided"
    end
  end

  defp build_system_message(agent) do
    """
    You are an AI assistant with access to various tools.
    Use the ReAct framework: Reason, Act, Observe.

    Available tools: #{list_available_tools()}
    Current task: #{agent.state[:current_task] || "No specific task"}
    """
  end

  defp list_available_tools() do
    Registry.list_tools()
    |> Enum.map(& &1.name())
    |> Enum.join(", ")
  end

  defp process_streaming_response(agent, stream_response, context) do
    # Process streaming tokens and handle tool calls
    # Update agent state with reasoning steps and actions
    # Return updated agent and directives
  end
end
```

#### 3. Updated Model Integration

```elixir
defmodule Jido.AI.Models.ReqLLM do
  @moduledoc """
  Model integration using ReqLLM's unified API.
  """

  alias Jido.AI.ReqLLM.Adapter

  @behaviour Jido.AI.Models.Model

  @impl true
  def chat(messages, options) do
    model_spec = Keyword.get(options, :model, "anthropic:claude-haiku-4-5")
    prompt = messages_to_prompt(messages)

    Adapter.generate_text(model_spec, prompt, options)
  end

  @impl true
  def complete(prompt, options) do
    model_spec = Keyword.get(options, :model, "anthropic:claude-haiku-4-5")

    Adapter.generate_text(model_spec, prompt, options)
  end

  @impl true
  def embed(text, options) do
    model_spec = Keyword.get(options, :model, "openai:text-embedding-3-small")

    Adapter.generate_embeddings(model_spec, [text], options)
  end

  @impl true
  def capabilities do
    %{
      streaming: true,
      tool_calling: true,
      structured_output: true,
      embeddings: true,
      providers: ReqLLM.Model.list_providers(),
      models: ReqLLM.Model.list_models()
    }
  end

  defp messages_to_prompt(messages) do
    messages
    |> Enum.map(fn
      %{role: "system", content: content} -> "System: #{content}"
      %{role: "user", content: content} -> "User: #{content}"
      %{role: "assistant", content: content} -> "Assistant: #{content}"
      _ -> ""
    end)
    |> Enum.join("\n")
  end
end
```

#### 4. Enhanced Tool System

```elixir
defmodule Jido.AI.Tools.Registry do
  @moduledoc """
  Enhanced tool registry that integrates with ReqLLM's tool calling.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register(tool_module) do
    GenServer.call(__MODULE__, {:register, tool_module})
  end

  def list_tools() do
    GenServer.call(__MODULE__, :list_tools)
  end

  def execute_tool(tool_name, params, context) do
    GenServer.call(__MODULE__, {:execute, tool_name, params, context})
  end

  def to_reqllm_tools() do
    GenServer.call(__MODULE__, :to_reqllm_tools)
  end

  @impl true
  def init(_opts) do
    {:ok, %{tools: %{}}}
  end

  @impl true
  def handle_call({:register, tool_module}, _from, state) do
    tool_info = %{
      module: tool_module,
      name: tool_module.name(),
      description: tool_module.description(),
      schema: tool_module.schema()
    }

    new_state = put_in(state.tools[tool_module.name()], tool_info)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_tools, _from, state) do
    {:reply, Map.values(state.tools), state}
  end

  @impl true
  def handle_call({:execute, tool_name, params, context}, _from, state) do
    case Map.get(state.tools, tool_name) do
      nil ->
        {:reply, {:error, :tool_not_found}, state}

      tool_info ->
        result = apply(tool_info.module, :execute, [params, context])
        {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:to_reqllm_tools, _from, state) do
    reqllm_tools =
      state.tools
      |> Map.values()
      |> Enum.map(&convert_to_reqllm_tool/1)

    {:reply, reqllm_tools, state}
  end

  defp convert_to_reqllm_tool(tool_info) do
    ReqLLM.tool(
      name: tool_info.name,
      description: tool_info.description,
      parameter_schema: tool_info.schema,
      callback: {tool_info.module, :execute, [:extra, :args]}
    )
  end
end
```

#### 5. Enhanced Memory and Context Management

```elixir
defmodule Jido.AI.Memory.Context do
  @moduledoc """
  Enhanced context management that integrates with ReqLLM's conversation tracking.
  """

  defstruct [
    :conversation_history,
    :current_task,
    :relevant_memories,
    :tool_results,
    :subagent_states,
    :reqllm_metadata
  ]

  def new() do
    %__MODULE__{
      conversation_history: [],
      current_task: nil,
      relevant_memories: [],
      tool_results: %{},
      subagent_states: %{},
      reqllm_metadata: %{}
    }
  end

  def add_message(context, role, content) do
    message = %{
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }

    %{context | conversation_history: context.conversation_history ++ [message]}
  end

  def add_reqllm_metadata(context, metadata) do
    %{context | reqllm_metadata: Map.merge(context.reqllm_metadata, metadata)}
  end

  def to_reqllm_context(context) do
    messages =
      context.conversation_history
      |> Enum.map(&convert_message/1)

    ReqLLM.Context.new(messages)
  end

  defp convert_message(%{role: role, content: content}) do
    case role do
      "system" -> ReqLLM.Message.system(content)
      "user" -> ReqLLM.Message.user(content)
      "assistant" -> ReqLLM.Message.assistant(content)
      _ -> ReqLLM.Message.user(content)
    end
  end
end
```

#### 6. Streaming AI Agent

```elixir
defmodule Jido.AI.Agents.StreamingAIAgent do
  @moduledoc """
  AI agent that leverages ReqLLM's streaming capabilities.
  """

  use Jido.Agent,
    name: "streaming_ai_agent",
    description: "AI agent with streaming responses",
    schema: [
      current_stream: [type: :map, default: %{}],
      streaming_status: [type: :atom, default: :idle],
      reqllm_config: [type: :map, default: %{}]
    ],
    strategy: Jido.AI.Strategies.ReAct,
    skills: [
      Jido.AI.Skills.LLMSkill,
      Jido.AI.Skills.StreamingSkill
    ]

  def start_stream(agent, prompt, opts \\ []) do
    model_spec = agent.state[:reqllm_config][:model] || "anthropic:claude-haiku-4-5"

    case Jido.AI.ReqLLM.Adapter.stream_text(model_spec, prompt, opts) do
      {:ok, stream_response} ->
        updated_agent = put_in(agent.state[:current_stream], stream_response)
        updated_agent = put_in(updated_agent.state[:streaming_status], :active)
        {updated_agent, []}

      {:error, reason} ->
        {agent, [%Jido.Agent.Directive.Error{error: reason}]}
    end
  end

  def get_stream_tokens(agent) do
    case agent.state[:current_stream] do
      %{tokens: tokens} -> tokens
      _ -> []
    end
  end

  def get_stream_usage(agent) do
    case agent.state[:current_stream] do
      %{usage: usage_fn} -> usage_fn.()
      _ -> nil
    end
  end

  def stop_stream(agent) do
    updated_agent = put_in(agent.state[:streaming_status], :completed)
    {updated_agent, []}
  end
end
```

## Integration Patterns

### 1. Streaming Chat Agent

```elixir
defmodule ChatAgent do
  use Jido.AI.Agents.StreamingAIAgent,
    name: "chat_agent",
    description: "Streaming chat agent",
    strategy: Jido.AI.Strategies.ReAct,
    skills: [
      Jido.AI.Skills.LLMSkill,
      Jido.AI.Skills.MemorySkill
    ]

  def chat(agent, message) do
    context = Jido.AI.Memory.Context.add_message(agent.state.context, "user", message)

    {updated_agent, _directives} = ChatAgent.cmd(agent, %{
      action: :chat,
      prompt: message,
      context: context
    })

    updated_agent
  end
end
```

### 2. Multi-Model Agent

```elixir
defmodule MultiModelAgent do
  use Jido.AI.Agents.AIAgent,
    name: "multi_model_agent",
    description: "Agent using multiple LLM models",
    strategy: Jido.AI.Strategies.Adaptive,
    skills: [
      Jido.AI.Skills.LLMSkill,
      Jido.AI.Skills.ModelSelectionSkill
    ]

  def with_model(agent, model_spec) do
    updated_config = put_in(agent.state[:reqllm_config][:model], model_spec)
    %{agent | state: Map.merge(agent.state, updated_config)}
  end

  def select_best_model(agent, task) do
    # Implement model selection logic based on task requirements
    # Consider model capabilities, cost, performance
    selected_model = select_model_for_task(task)
    with_model(agent, selected_model)
  end
end
```

### 3. Tool-Enabled Agent

```elixir
defmodule ToolEnabledAgent do
  use Jido.AI.Agents.AIAgent,
    name: "tool_enabled_agent",
    description: "Agent with tool calling capabilities",
    strategy: Jido.AI.Strategies.ReAct,
    skills: [
      Jido.AI.Skills.LLMSkill,
      Jido.AI.Skills.ToolCallingSkill
    ]

  # Tools are automatically registered and available to the LLM
  def available_tools(agent) do
    Jido.AI.Tools.Registry.list_tools()
  end
end
```

## Configuration

### 1. ReqLLM Configuration

```elixir
# config/config.exs
config :jido_ai,
  req_llm: [
    default_model: "anthropic:claude-haiku-4-5",
    streaming: true,
    tools: true,
    structured_output: true
  ],
  models: [
    fast_model: "anthropic:claude-haiku-4-5",
    capable_model: "anthropic:claude-3-opus-20240229",
    reasoning_model: "openai:o1-preview"
  ]
```

### 2. Provider Configuration

```elixir
# Configure multiple providers
config :req_llm,
  providers: [
    openai: [
      api_key: System.get_env("OPENAI_API_KEY"),
      base_url: "https://api.openai.com/v1"
    ],
    anthropic: [
      api_key: System.get_env("ANTHROPIC_API_KEY")
    ]
  ]
```

## Advanced Features

### 1. Cost-Aware Model Selection

```elixir
defmodule Jido.AI.CostManager do
  def select_model_for_task(task, budget) do
    # Analyze task complexity and budget constraints
    # Select appropriate model based on cost/performance trade-offs
    available_models = ReqLLM.Model.list_models()

    # Implement cost-aware selection logic
    optimal_model = find_optimal_model(available_models, task, budget)
    optimal_model
  end

  defp find_optimal_model(models, task, budget) do
    # Sort models by cost and capability
    # Return best model within budget
  end
end
```

### 2. Streaming with LiveView Integration

```elixir
defmodule MyAppWeb.LiveAI do
  use MyAppWeb, :live_view

  def handle_event("send_message", %{"message" => message}, socket) do
    agent = socket.assigns.agent

    # Start streaming response
    {updated_agent, _directives} =
      ChatAgent.start_stream(agent, message)

    # Update socket with streaming state
    socket = assign(socket, agent: updated_agent, streaming: true)

    # Process stream in background
    Task.start(fn ->
      process_stream(socket.id, updated_agent)
    end)

    {:noreply, socket}
  end

  defp process_stream(socket_id, agent) do
    tokens = ChatAgent.get_stream_tokens(agent)

    Enum.each(tokens, fn token ->
      # Send token to LiveView via pub/sub
      MyAppWeb.Endpoint.broadcast("ai:#{socket_id}", "token", %{token: token})
    end)

    # Send completion signal
    MyAppWeb.Endpoint.broadcast("ai:#{socket_id}", "complete", %{})
  end
end
```

### 3. Metadata-Driven Analytics

```elixir
defmodule Jido.AI.Analytics do
  require Logger

  def track_usage(agent, response) do
    metadata = response.reqllm_metadata

    Logger.info("""
    AI Usage:
    - Model: #{metadata.model}
    - Provider: #{metadata.provider}
    - Input tokens: #{metadata.input_tokens}
    - Output tokens: #{metadata.output_tokens}
    - Cost: $#{metadata.cost}
    - Duration: #{metadata.duration}ms
    """)

    # Store analytics data
    store_analytics(agent.id, metadata)
  end

  defp store_analytics(agent_id, metadata) do
    # Implement analytics storage
  end
end
```

## Testing

### 1. Unit Tests with ReqLLM Mocking

```elixir
defmodule Jido.AI.Strategies.ReActTest do
  use ExUnit.Case

  alias Jido.AI.Strategies.ReAct
  alias Jido.AI.ReqLLM.Adapter

  test "processes streaming response correctly" do
    # Mock ReqLLM responses
    with_mock Adapter, stream_text: fn _, _, _ ->
      {:ok, mock_stream_response()}
    end do
      agent = TestAgent.new()
      {agent, directives} = ReAct.cmd(agent, [%{prompt: "test"}], %{})

      assert length(directives) > 0
      assert agent.state[:streaming_status] == :active
    end
  end

  defp mock_stream_response do
    %{
      id: "test-stream",
      tokens: ["Hello", " world", "!"],
      usage: fn -> %{input_tokens: 5, output_tokens: 3} end
    }
  end
end
```

### 2. Integration Tests

```elixir
defmodule Jido.AI.IntegrationTest do
  use ExUnit.Case

  test "AI agent completes complex task with streaming" do
    agent = ComplexAIAgent.new()

    {agent, _directives} = ComplexAIAgent.cmd(agent, %{
      action: :complex_task,
      prompt: "Solve this step by step"
    })

    # Verify streaming behavior
    assert agent.state[:streaming_status] == :active

    # Verify completion
    :timer.sleep(1000)  # Wait for streaming to complete
    assert agent.state[:task_status] == :completed
  end
end
```

## Performance Optimization

### 1. Connection Pooling

```elixir
# Configure ReqLLM connection pooling
config :req_llm,
  finch: [
    name: JidoAI.Finch,
    pools: %{
      :default => [protocols: [:http1], size: 1, count: 16]
    }
  ]
```

### 2. Caching

```elixir
defmodule Jido.AI.Cache do
  use GenServer

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def put(key, value, ttl \\ :timer.minutes(5)) do
    GenServer.call(__MODULE__, {:put, key, value, ttl})
  end

  # Cache ReqLLM responses
  def cache_response(model_spec, prompt, response) do
    cache_key = generate_cache_key(model_spec, prompt)
    put(cache_key, response, :timer.minutes(30))
  end

  defp generate_cache_key(model_spec, prompt) do
    :crypto.hash(:sha256, "#{model_spec}:#{prompt}")
    |> Base.encode64()
  end
end
```

## Monitoring and Observability

### 1. ReqLLM Telemetry Integration

```elixir
defmodule Jido.AI.Telemetry do
  require Logger

  def attach_reqllm_handlers() do
    :telemetry.attach_many("jido-ai-reqllm", [
      [:req_llm, :token_usage],
      [:req_llm, :request, :start],
      [:req_llm, :request, :stop],
      [:req_llm, :request, :exception]
    ], &handle_event/4, nil)
  end

  def handle_event([:req_llm, :token_usage], measurements, metadata, _config) do
    Logger.info("""
    ReqLLM Token Usage:
    - Model: #{metadata.model}
    - Input tokens: #{measurements.input_tokens}
    - Output tokens: #{measurements.output_tokens}
    - Cost: $#{measurements.total_cost}
    """)
  end

  def handle_event([:req_llm, :request, :start], _measurements, metadata, _config) do
    Logger.debug("ReqLLM request started: #{metadata.model}")
  end

  def handle_event([:req_llm, :request, :stop], measurements, metadata, _config) do
    Logger.debug("ReqLLM request completed in #{measurements.duration}ms")
  end

  def handle_event([:req_llm, :request, :exception], measurements, metadata, _config) do
    Logger.error("ReqLLM request failed: #{metadata.reason}")
  end
end
```

## Conclusion

This updated architecture integrates ReqLLM as the primary LLM access layer for Jido AI, providing:

1. **Unified LLM Access**: Single interface for multiple LLM providers
2. **Streaming Capabilities**: Real-time response streaming with rich metadata
3. **Tool Calling**: Native support for function calling
4. **Structured Output**: Schema-based response generation
5. **Cost Tracking**: Built-in usage and cost monitoring
6. **Model Registry**: Access to 45+ providers and 665+ models
7. **Production Ready**: Comprehensive error handling and telemetry

The architecture maintains Jido's core principles while leveraging ReqLLM's powerful features to create a robust, scalable AI extension that can handle complex reasoning tasks, multi-agent coordination, and real-time streaming interactions.

The integration ensures that Jido AI can:

- Access multiple LLM providers through a unified API
- Stream responses in real-time for interactive applications
- Use tool calling for external system integration
- Track usage and costs for optimization
- Scale horizontally with connection pooling and caching
- Monitor performance with comprehensive telemetry

This design provides a solid foundation for building sophisticated AI applications with Jido while maintaining flexibility for future enhancements and new AI capabilities.
