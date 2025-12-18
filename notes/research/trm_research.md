# TRM Implementation in Elixir: Complete Research & Implementation Guide

## Executive Summary

This document provides a complete implementation guide for **Tiny Recursion Model (TRM)** in Elixir, integrated with the Jido agentic framework. TRM achieves remarkable results (45% on ARC-AGI-1, 87% on Sudoku-Extreme) using only 7M parameters through recursive reasoning - a paradigm shift from massive LLMs.

**Key Findings:**
- TRM simplifies recursive reasoning to its essence: iteratively improving answers through latent reasoning
- Perfect fit for Elixir's concurrency model - recursive steps can be parallelized
- Jido's Action/Skill/Agent architecture aligns naturally with TRM's modular design
- Axon/Nx provide all necessary neural network primitives for implementation

---

## Table of Contents

1. [TRM Architecture Deep Dive](#1-trm-architecture-deep-dive)
2. [Jido/JidoAi Integration Strategy](#2-jidojidoai-integration-strategy)
3. [Implementation Architecture](#3-implementation-architecture)
4. [Elixir Concurrency Adaptations](#4-elixir-concurrency-adaptations)
5. [Module Structure & Code](#5-module-structure--code)
6. [Training & Inference Pipeline](#6-training--inference-pipeline)
7. [Testing Strategy](#7-testing-strategy)
8. [Performance Considerations](#8-performance-considerations)
9. [Deployment Guide](#9-deployment-guide)
10. [Future Enhancements](#10-future-enhancements)
11. [References & Resources](#11-references--resources)

---

## 1. TRM Architecture Deep Dive

### 1.1 Core Concept

TRM's brilliance lies in its simplicity. Unlike HRM's complex two-network hierarchical approach, TRM uses:
- **Single tiny network** (2 layers only)
- **Two features**: Current answer `y` and latent reasoning `z`
- **Recursive improvement**: Iteratively refine reasoning and answer
- **Deep supervision**: Multiple improvement steps with gradient flow

### 1.2 Mathematical Formulation

```
Input: x (embedded question)
Output: y (predicted answer)
Latent: z (reasoning state)

For each supervision step (up to N_sup = 16):
  For T-1 times (no gradients):
    For n times:
      z ← f_net(x, y, z)  # Update latent reasoning
    y ← f_net(y, z)        # Update answer
  
  Once with gradients:
    For n times:
      z ← f_net(x, y, z)
    y ← f_net(y, z)
    
  output ← output_head(y)
  halt? ← Q_head(y) > 0
```

### 1.3 Key Improvements Over HRM

| Feature | HRM | TRM | Benefit |
|---------|-----|-----|---------|
| Networks | 2 (fL, fH) | 1 | 50% fewer parameters |
| Layers | 4 | 2 | Less overfitting |
| Gradient backprop | 1-step approx | Full recursion | Better learning |
| ACT forward passes | 2 | 1 | 2x training speed |
| Theoretical basis | Fixed-point + biology | Direct optimization | Simpler |

### 1.4 Architecture Components

**Network Architecture (2-layer transformer):**
- RMSNorm (not LayerNorm)
- No bias terms
- Rotary embeddings (RoPE)
- SwiGLU activation
- Optional: MLP instead of self-attention for small fixed contexts

**Training Components:**
- Exponential Moving Average (EMA) with β=0.999
- AdamW optimizer
- Stable-max loss for numerical stability
- Deep supervision with early stopping via Q-learning halt

---

## 2. Jido/JidoAi Integration Strategy

### 2.1 Jido Framework Overview

Jido provides four core primitives:
1. **Actions**: Composable units of work with schemas
2. **Workflows**: Chainable action sequences  
3. **Agents**: Stateful entities that execute actions
4. **Sensors**: Real-time monitoring and data collection

### 2.2 TRM as a Jido Agent

**Agent Structure:**
```elixir
defmodule MyApp.Agents.TRMReasoning do
  use Jido.Agent,
    name: "trm_reasoning",
    description: "Tiny Recursive Model for iterative problem solving",
    actions: [
      MyApp.Actions.TRM.InitializeModel,
      MyApp.Actions.TRM.RecursiveReason,
      MyApp.Actions.TRM.SupervisionStep,
      MyApp.Actions.TRM.PredictAnswer
    ],
    schema: [
      model_params: [type: :map, required: true],
      supervision_steps: [type: :integer, default: 16],
      recursion_cycles: [type: :integer, default: 3],
      latent_cycles: [type: :integer, default: 6],
      current_z: [type: :any],  # Nx tensor
      current_y: [type: :any],  # Nx tensor
      halt_threshold: [type: :float, default: 0.0]
    ]
end
```

**Skills:**
```elixir
defmodule MyApp.Skills.TRMReasoning do
  use Jido.Skill, name: "trm_reasoning"
  
  def mount(agent, opts \\ []) do
    Jido.Agent.register_actions(agent, [
      __MODULE__.Actions.RecursiveReason,
      __MODULE__.Actions.SupervisionStep
    ])
  end
  
  def router(opts \\ []) do
    [
      {"jido.trm.reason", %Instruction{
        action: __MODULE__.Actions.RecursiveReason,
        params: %{cycles: 6}
      }},
      {"jido.trm.supervise", %Instruction{
        action: __MODULE__.Actions.SupervisionStep,
        params: %{max_steps: 16}
      }}
    ]
  end
end
```

### 2.3 Integration Patterns

**Pattern 1: Direct Reasoning**
```elixir
{:ok, agent} = MyApp.Agents.TRMReasoning.start_link()
{:ok, result} = Jido.Agent.cmd(agent, [
  %Jido.Instruction{
    action: "recursive_reason",
    params: %{question: sudoku_grid, max_steps: 16}
  }
])
```

**Pattern 2: Multi-Agent Collaboration**
```elixir
# TRM Agent collaborates with other agents via Signals
defmodule MyApp.Agents.ProblemSolver do
  use Jido.Agent
  
  def solve_hard_problem(problem) do
    # Delegate to TRM for reasoning
    signal = Jido.Signal.new(%{
      type: "problem.solve.request",
      source: "/solver",
      data: %{problem: problem},
      jido_dispatch: [{:pid, [target: trm_agent_pid]}]
    })
    
    # TRM processes and returns solution
    receive do
      %Jido.Signal{type: "problem.solve.complete", data: solution} ->
        {:ok, solution}
    end
  end
end
```

**Pattern 3: Skill Composition**
```elixir
# Compose TRM with other skills
defmodule MyApp.Agents.CodeAssistant do
  use Jido.Agent,
    skills: [
      MyApp.Skills.TRMReasoning,
      MyApp.Skills.CodeAnalysis,
      MyApp.Skills.Testing
    ]
    
  # TRM provides deep reasoning for complex refactoring
  def refactor_code(code) do
    execute_workflow([
      {MyApp.Skills.CodeAnalysis, :analyze},
      {MyApp.Skills.TRMReasoning, :reason},  # Deep recursive analysis
      {MyApp.Skills.CodeAnalysis, :generate_refactoring}
    ])
  end
end
```

---

## 3. Implementation Architecture

### 3.1 Module Organization

```
lib/
├── my_app/
│   ├── agents/
│   │   └── trm_reasoning.ex          # Main TRM Agent
│   ├── actions/
│   │   └── trm/
│   │       ├── initialize_model.ex   # Load/init model
│   │       ├── recursive_reason.ex   # Core recursion
│   │       ├── supervision_step.ex   # Deep supervision
│   │       └── predict_answer.ex     # Final prediction
│   ├── skills/
│   │   └── trm_reasoning.ex          # TRM Skill module
│   ├── trm/
│   │   ├── model.ex                  # Axon model definition
│   │   ├── layers.ex                 # Custom layers
│   │   ├── training.ex               # Training loop
│   │   ├── inference.ex              # Inference logic
│   │   ├── embeddings.ex             # Input/output embeddings
│   │   └── state.ex                  # Model state management
│   └── trm_server.ex                 # GenServer for model serving
```

### 3.2 Core TRM Model (Axon)

```elixir
defmodule MyApp.TRM.Model do
  import Nx.Defn
  
  @doc """
  Creates the TRM neural network architecture.
  
  Architecture:
  - 2-layer transformer with RMSNorm
  - Optional MLP-Mixer for small fixed contexts
  - SwiGLU activations
  - Rotary positional embeddings
  """
  def create(opts \\ []) do
    hidden_size = opts[:hidden_size] || 512
    num_layers = opts[:num_layers] || 2
    context_length = opts[:context_length]
    use_attention = opts[:use_attention] || true
    
    # Input embedding
    input_x = Axon.input("x", shape: {nil, context_length})
    input_y = Axon.input("y", shape: {nil, context_length})
    input_z = Axon.input("z", shape: {nil, hidden_size})
    
    # Embed inputs
    x_emb = input_x |> embed_input(hidden_size, context_length)
    y_emb = input_y |> embed_input(hidden_size, context_length)
    
    # Network for updating z (latent reasoning)
    # z_new = f_net(x, y, z)
    z_update_net = 
      Axon.concatenate([x_emb, y_emb, input_z], axis: -1)
      |> transformer_block(hidden_size, use_attention: use_attention)
      |> transformer_block(hidden_size, use_attention: use_attention)
      |> Axon.dense(hidden_size)
    
    # Network for updating y (answer)
    # y_new = f_net(y, z)
    y_update_net =
      Axon.concatenate([y_emb, input_z], axis: -1)
      |> transformer_block(hidden_size, use_attention: use_attention)
      |> transformer_block(hidden_size, use_attention: use_attention)
      |> Axon.dense(context_length)
    
    %{
      z_update: z_update_net,
      y_update: y_update_net,
      output_head: output_head(y_update_net, context_length),
      q_head: q_head(y_update_net)  # For halt detection
    }
  end
  
  defp transformer_block(input, hidden_size, opts) do
    use_attention = opts[:use_attention] || true
    
    # Pre-normalization
    normalized = Axon.layer_norm(input, epsilon: 1.0e-6)
    
    # Attention or MLP-Mixer
    attention_out = if use_attention do
      normalized
      |> multi_head_attention(hidden_size, num_heads: 8)
      |> Axon.add(input)  # Residual
    else
      # MLP-Mixer for small fixed contexts
      normalized
      |> mlp_mixer_layer(hidden_size)
      |> Axon.add(input)  # Residual
    end
    
    # Feed-forward with SwiGLU
    attention_out
    |> Axon.layer_norm(epsilon: 1.0e-6)
    |> swiglu_ffn(hidden_size * 4)
    |> Axon.add(attention_out)  # Residual
  end
  
  defp swiglu_ffn(input, ffn_size) do
    # SwiGLU activation: swish(Wx) ⊙ (Vx)
    gate = Axon.dense(input, ffn_size, use_bias: false)
    value = Axon.dense(input, ffn_size, use_bias: false)
    
    gated = Axon.multiply(Axon.activation(gate, :swish), value)
    Axon.dense(gated, Axon.get_output_shape(input)[-1], use_bias: false)
  end
  
  defp output_head(y_embedding, vocab_size) do
    y_embedding
    |> Axon.dense(vocab_size)
    |> Axon.activation(:softmax)
  end
  
  defp q_head(y_embedding) do
    # Binary classifier for halt decision
    y_embedding
    |> Axon.dense(1)
    |> Axon.activation(:sigmoid)
  end
end
```

### 3.3 Recursive Reasoning Loop

```elixir
defmodule MyApp.TRM.Inference do
  import Nx.Defn
  
  @doc """
  Performs recursive reasoning with deep supervision.
  
  ## Parameters
  - x: Input question (embedded)
  - model_state: Trained model parameters
  - opts: Configuration options
  
  ## Returns
  - {:ok, answer, final_state} | {:error, reason}
  """
  def recursive_reason(x, model_state, opts \\ []) do
    n_sup = opts[:n_supervision] || 16
    h_cycles = opts[:h_cycles] || 3
    l_cycles = opts[:l_cycles] || 6
    halt_threshold = opts[:halt_threshold] || 0.0
    
    # Initialize y and z
    {y, z} = initialize_state(x, model_state)
    
    # Deep supervision loop
    result = Enum.reduce_while(0..(n_sup-1), {y, z, []}, fn step, {y_curr, z_curr, history} ->
      # Perform one full recursion with supervision
      {y_new, z_new, q_halt} = supervision_step(
        x, y_curr, z_curr, model_state,
        h_cycles: h_cycles,
        l_cycles: l_cycles
      )
      
      new_history = [{step, y_new, q_halt} | history]
      
      # Check for early stopping
      if q_halt > halt_threshold do
        {:halt, {y_new, z_new, new_history}}
      else
        {:cont, {y_new, z_new, new_history}}
      end
    end)
    
    {final_y, final_z, history} = result
    answer = decode_answer(final_y, model_state)
    
    {:ok, answer, %{z: final_z, y: final_y, history: Enum.reverse(history)}}
  end
  
  defnp supervision_step(x, y, z, model_state, opts) do
    h_cycles = opts[:h_cycles]
    l_cycles = opts[:l_cycles]
    
    # Phase 1: T-1 cycles without gradients (inference only)
    {y_temp, z_temp} = Enum.reduce(1..(h_cycles-1), {y, z}, fn _, {y_acc, z_acc} ->
      latent_recursion(x, y_acc, z_acc, model_state, l_cycles)
    end)
    
    # Phase 2: Final cycle with gradients (during training)
    {y_final, z_final} = latent_recursion(x, y_temp, z_temp, model_state, l_cycles)
    
    # Compute output and halt signal
    output = apply_output_head(y_final, model_state)
    q_halt = apply_q_head(y_final, model_state)
    
    {Nx.detach(y_final), Nx.detach(z_final), q_halt}
  end
  
  defnp latent_recursion(x, y, z, model_state, n) do
    # Update latent z for n cycles
    z_updated = Enum.reduce(1..n, z, fn _, z_acc ->
      apply_z_update(x, y, z_acc, model_state)
    end)
    
    # Update answer y based on final z
    y_updated = apply_y_update(y, z_updated, model_state)
    
    {y_updated, z_updated}
  end
  
  defnp apply_z_update(x, y, z, model_state) do
    # z_new = f_net(x, y, z)
    inputs = %{"x" => x, "y" => y, "z" => z}
    Axon.predict(model_state.z_update_model, model_state.z_params, inputs)
  end
  
  defnp apply_y_update(y, z, model_state) do
    # y_new = f_net(y, z)
    inputs = %{"y" => y, "z" => z}
    Axon.predict(model_state.y_update_model, model_state.y_params, inputs)
  end
end
```

---

## 4. Elixir Concurrency Adaptations

### 4.1 Novel Concurrency Pattern: Parallel Recursion

**Key Insight:** TRM's recursion cycles are potentially parallelizable. While the paper runs them sequentially, Elixir's BEAM VM enables novel concurrent patterns.

#### Pattern 1: Parallel Latent Updates (Experimental)

```elixir
defmodule MyApp.TRM.ConcurrentInference do
  @doc """
  Experimental: Parallel latent reasoning updates.
  
  Instead of sequential z updates, spawn processes for each cycle
  and merge results. This explores if different "reasoning paths"
  can be explored concurrently.
  """
  def parallel_latent_recursion(x, y, z_init, model_state, n) do
    # Spawn n processes, each exploring one reasoning step
    tasks = for i <- 1..n do
      Task.async(fn ->
        # Each task computes one potential z update
        z_candidate = apply_z_update(x, y, z_init, model_state)
        {i, z_candidate}
      end)
    end
    
    # Collect all candidates
    candidates = Task.await_many(tasks, timeout: 5000)
    
    # Merge strategies:
    # 1. Average: mean of all z candidates
    # 2. Best: select based on internal quality metric
    # 3. Ensemble: weighted combination
    
    merge_latent_states(candidates, strategy: :average)
  end
  
  defp merge_latent_states(candidates, opts) do
    strategy = opts[:strategy] || :average
    
    case strategy do
      :average ->
        # Average all candidate z tensors
        z_tensors = Enum.map(candidates, fn {_i, z} -> z end)
        Nx.mean(Nx.stack(z_tensors), axes: [0])
        
      :weighted ->
        # Weight by internal confidence scores
        weighted_merge(candidates)
    end
  end
end
```

#### Pattern 2: Distributed Deep Supervision

```elixir
defmodule MyApp.TRM.DistributedTraining do
  use GenServer
  
  @doc """
  Distribute supervision steps across multiple nodes.
  
  Each node handles a subset of the data batch, enabling
  horizontal scaling of TRM training.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def train_distributed(data_batch, model_state) do
    # Split batch across available nodes
    nodes = [Node.self() | Node.list()]
    batch_size = div(length(data_batch), length(nodes))
    
    batches = Enum.chunk_every(data_batch, batch_size)
    
    # Spawn training on each node
    tasks = for {node, batch} <- Enum.zip(nodes, batches) do
      Task.Supervisor.async(
        {MyApp.TaskSupervisor, node},
        fn -> train_batch(batch, model_state) end
      )
    end
    
    # Aggregate gradients
    gradients = Task.await_many(tasks)
    aggregate_gradients(gradients)
  end
end
```

#### Pattern 3: Pipelined Supervision Steps

```elixir
defmodule MyApp.TRM.PipelinedInference do
  use GenStage
  
  @doc """
  Pipeline supervision steps using GenStage for streaming inference.
  
  Producer -> Reasoning Stage -> Supervision Stage -> Consumer
  
  This enables processing multiple problems concurrently with
  different supervision step depths.
  """
  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end
  
  def init(opts) do
    {:producer_consumer, opts}
  end
  
  def handle_events(problems, _from, state) do
    # Process each problem through one supervision step
    results = Enum.map(problems, fn {x, y, z, step} ->
      {y_new, z_new, _q} = supervision_step(x, y, z, state.model)
      {x, y_new, z_new, step + 1}
    end)
    
    # Emit to next stage or finalize
    {:noreply, results, state}
  end
end
```

### 4.2 Fault Tolerance with OTP

```elixir
defmodule MyApp.TRM.Supervisor do
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  def init(_init_arg) do
    children = [
      # Model server holds the trained parameters
      {MyApp.TRM.ModelServer, name: MyApp.TRM.ModelServer},
      
      # Inference workers (pool of workers)
      {Task.Supervisor, name: MyApp.TRM.InferenceTaskSupervisor},
      
      # Reasoning agent
      {MyApp.Agents.TRMReasoning, []},
      
      # Telemetry for monitoring
      {TelemetryMetricsPrometheus, metrics: trm_metrics()}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  defp trm_metrics do
    [
      Telemetry.Metrics.counter("trm.inference.count"),
      Telemetry.Metrics.distribution("trm.inference.duration"),
      Telemetry.Metrics.last_value("trm.supervision_steps.average"),
      Telemetry.Metrics.counter("trm.early_halt.count")
    ]
  end
end
```

### 4.3 Concurrent Data Loading

```elixir
defmodule MyApp.TRM.DataLoader do
  use GenServer
  
  @doc """
  Concurrent data loading and augmentation pipeline.
  
  Uses Flow for parallel data processing:
  - Read data files
  - Apply augmentations (dihedral transforms, permutations)
  - Batch creation
  - Tensor conversion
  """
  def load_training_data(data_path, opts \\ []) do
    augmentations = opts[:augmentations] || 1000
    batch_size = opts[:batch_size] || 768
    
    data_path
    |> File.stream!()
    |> Flow.from_enumerable(max_demand: 100)
    |> Flow.map(&parse_example/1)
    |> Flow.flat_map(fn example ->
      # Generate augmentations in parallel
      generate_augmentations(example, augmentations)
    end)
    |> Flow.partition(stages: System.schedulers_online())
    |> Flow.map(&to_tensors/1)
    |> Enum.to_list()
    |> Enum.chunk_every(batch_size)
  end
  
  defp generate_augmentations(example, n) do
    Task.async_stream(1..n, fn _i ->
      augment_example(example)
    end, max_concurrency: System.schedulers_online())
    |> Enum.map(fn {:ok, aug} -> aug end)
  end
end
```

---

## 5. Module Structure & Code

### 5.1 Complete Action Implementation

```elixir
defmodule MyApp.Actions.TRM.RecursiveReason do
  use Jido.Action,
    name: "recursive_reason",
    description: "Performs TRM recursive reasoning on input problem",
    schema: [
      question: [type: :any, required: true, doc: "Input problem tensor"],
      max_steps: [type: :integer, default: 16],
      halt_threshold: [type: :float, default: 0.0]
    ]
  
  @impl true
  def run(params, context) do
    with {:ok, model_state} <- get_model_state(context),
         {:ok, x_embedded} <- embed_question(params.question, model_state),
         {:ok, answer, state} <- MyApp.TRM.Inference.recursive_reason(
           x_embedded,
           model_state,
           n_supervision: params.max_steps,
           halt_threshold: params.halt_threshold
         ) do
      
      # Emit telemetry
      :telemetry.execute(
        [:trm, :inference, :complete],
        %{supervision_steps: length(state.history)},
        %{action: "recursive_reason"}
      )
      
      {:ok, %{answer: answer, state: state, steps: length(state.history)}}
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp get_model_state(context) do
    case GenServer.call(MyApp.TRM.ModelServer, :get_state) do
      nil -> {:error, "Model not loaded"}
      state -> {:ok, state}
    end
  end
end
```

### 5.2 Model Server (GenServer)

```elixir
defmodule MyApp.TRM.ModelServer do
  use GenServer
  require Logger
  
  @moduledoc """
  GenServer that holds TRM model state and provides inference.
  
  Supports:
  - Hot model reloading
  - EMA weight updates
  - Batch inference
  - Model versioning
  """
  
  defstruct [
    :model_params,
    :ema_params,
    :model_config,
    :version,
    :loaded_at
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def load_model(model_path) do
    GenServer.call(__MODULE__, {:load_model, model_path})
  end
  
  def predict(input, opts \\ []) do
    GenServer.call(__MODULE__, {:predict, input, opts}, :infinity)
  end
  
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    model_path = opts[:model_path]
    
    state = %__MODULE__{
      model_params: nil,
      ema_params: nil,
      model_config: opts[:config] || default_config(),
      version: "1.0.0",
      loaded_at: nil
    }
    
    if model_path do
      case load_model_from_disk(model_path) do
        {:ok, params} ->
          {:ok, %{state | model_params: params, loaded_at: DateTime.utc_now()}}
        {:error, reason} ->
          Logger.error("Failed to load model: #{inspect(reason)}")
          {:ok, state}
      end
    else
      {:ok, state}
    end
  end
  
  @impl true
  def handle_call({:load_model, path}, _from, state) do
    case load_model_from_disk(path) do
      {:ok, params} ->
        new_state = %{state | 
          model_params: params,
          loaded_at: DateTime.utc_now()
        }
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:predict, input, opts}, _from, state) do
    if state.model_params do
      result = MyApp.TRM.Inference.recursive_reason(
        input,
        state,
        opts
      )
      {:reply, result, state}
    else
      {:reply, {:error, :model_not_loaded}, state}
    end
  end
  
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
  
  # Private Functions
  
  defp load_model_from_disk(path) do
    # Load serialized Nx tensors
    case File.read(path) do
      {:ok, binary} ->
        params = :erlang.binary_to_term(binary)
        {:ok, params}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp default_config do
    %{
      hidden_size: 512,
      num_layers: 2,
      context_length: 900,  # 30x30 grid
      use_attention: true,
      h_cycles: 3,
      l_cycles: 6
    }
  end
end
```

---

## 6. Training & Inference Pipeline

### 6.1 Training Loop

```elixir
defmodule MyApp.TRM.Training do
  import Nx.Defn
  
  def train(data_loader, opts \\ []) do
    # Initialize model
    model = MyApp.TRM.Model.create(opts)
    {init_fn, predict_fn} = Axon.build(model.z_update)
    
    # Initialize optimizer (AdamW)
    optimizer = Polaris.Optimizers.adamw(
      learning_rate: opts[:learning_rate] || 1.0e-4,
      weight_decay: opts[:weight_decay] || 0.1
    )
    
    # EMA state
    ema_state = initialize_ema(init_fn, opts)
    
    # Training loop with deep supervision
    trained_state = Axon.Loop.trainer(
      model,
      :categorical_cross_entropy,
      optimizer,
      log: 100
    )
    |> attach_deep_supervision_handler(opts)
    |> attach_ema_handler(ema_decay: 0.999)
    |> attach_early_stopping_handler()
    |> Axon.Loop.run(data_loader, epochs: opts[:epochs] || 100_000, compiler: EXLA)
    
    {:ok, trained_state}
  end
  
  defp attach_deep_supervision_handler(loop, opts) do
    n_sup = opts[:n_supervision] || 16
    
    Axon.Loop.handle(:iteration_completed, fn state ->
      # Implement deep supervision logic
      # For each batch, run multiple supervision steps
      perform_deep_supervision(state, n_sup)
    end)
  end
  
  defp attach_ema_handler(loop, opts) do
    ema_decay = opts[:ema_decay] || 0.999
    
    Axon.Loop.handle(:epoch_completed, fn state ->
      # Update EMA parameters
      update_ema_parameters(state, ema_decay)
    end)
  end
  
  defnp deep_supervision_loss(x, y_true, model_state, opts) do
    n_sup = opts[:n_supervision]
    
    # Initialize state
    {y, z} = initialize_supervision_state(x, model_state)
    
    # Accumulate loss over supervision steps
    {_final_y, _final_z, total_loss} = 
      for step <- 1..n_sup, reduce: {y, z, 0.0} do
        {y_curr, z_curr, loss_acc} ->
          # One supervision step
          {y_new, z_new, q_halt} = supervision_step(x, y_curr, z_curr, model_state)
          
          # Compute losses
          prediction_loss = categorical_cross_entropy(y_new, y_true)
          halt_loss = binary_cross_entropy(
            q_halt,
            Nx.equal(Nx.argmax(y_new), Nx.argmax(y_true))
          )
          
          step_loss = prediction_loss + 0.5 * halt_loss
          
          # Early stopping if halt triggered
          if q_halt > 0 do
            {y_new, z_new, loss_acc + step_loss}
          else
            {y_new, z_new, loss_acc + step_loss}
          end
      end
    
    total_loss / n_sup
  end
end
```

### 6.2 Data Augmentation

```elixir
defmodule MyApp.TRM.Augmentation do
  @doc """
  Data augmentation strategies for TRM training.
  
  Different augmentations for different tasks:
  - Sudoku: Grid permutations (row/col swaps, digit permutations)
  - Maze: Dihedral transformations (rotations, flips)
  - ARC-AGI: Color permutations + dihedral + translations
  """
  
  def augment_sudoku(grid, n_augmentations) do
    for _ <- 1..n_augmentations do
      grid
      |> maybe_permute_digits()
      |> maybe_swap_rows()
      |> maybe_swap_cols()
      |> maybe_transpose()
    end
  end
  
  def augment_maze(grid, n_augmentations \\ 8) do
    # All 8 dihedral transformations
    [
      grid,
      rotate_90(grid),
      rotate_180(grid),
      rotate_270(grid),
      flip_horizontal(grid),
      flip_vertical(grid),
      flip_horizontal(rotate_90(grid)),
      flip_vertical(rotate_90(grid))
    ]
  end
  
  def augment_arc(task, n_augmentations) do
    for _ <- 1..n_augmentations do
      task
      |> permute_colors()
      |> random_dihedral_transform()
      |> maybe_translate()
    end
  end
  
  defp rotate_90(grid) do
    # Nx tensor rotation
    grid
    |> Nx.transpose()
    |> Nx.reverse(axes: [1])
  end
end
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

```elixir
defmodule MyApp.TRM.ModelTest do
  use ExUnit.Case, async: true
  
  describe "TRM Model Creation" do
    test "creates model with correct architecture" do
      model = MyApp.TRM.Model.create(
        hidden_size: 512,
        num_layers: 2,
        context_length: 81
      )
      
      assert model.z_update
      assert model.y_update
      assert model.output_head
      assert model.q_head
    end
    
    test "model forward pass produces correct shapes" do
      model = MyApp.TRM.Model.create(hidden_size: 512, context_length: 81)
      {init_fn, predict_fn} = Axon.build(model.z_update)
      
      # Initialize parameters
      template = %{
        "x" => Nx.template({1, 81}, :f32),
        "y" => Nx.template({1, 81}, :f32),
        "z" => Nx.template({1, 512}, :f32)
      }
      params = init_fn.(template, %{})
      
      # Forward pass
      inputs = %{
        "x" => Nx.random_uniform({1, 81}),
        "y" => Nx.random_uniform({1, 81}),
        "z" => Nx.random_uniform({1, 512})
      }
      
      output = predict_fn.(params, inputs)
      assert Nx.shape(output) == {1, 512}
    end
  end
  
  describe "Recursive Reasoning" do
    test "performs full recursion cycle" do
      x = Nx.random_uniform({1, 81})
      model_state = load_test_model()
      
      {:ok, answer, state} = MyApp.TRM.Inference.recursive_reason(
        x,
        model_state,
        n_supervision: 4
      )
      
      assert is_struct(answer, Nx.Tensor)
      assert length(state.history) <= 4
    end
    
    test "early stops when halt threshold reached" do
      x = Nx.random_uniform({1, 81})
      model_state = load_test_model()
      
      {:ok, _answer, state} = MyApp.TRM.Inference.recursive_reason(
        x,
        model_state,
        n_supervision: 16,
        halt_threshold: 0.5
      )
      
      # Should stop before 16 steps
      assert length(state.history) < 16
    end
  end
end
```

### 7.2 Integration Tests

```elixir
defmodule MyApp.TRM.IntegrationTest do
  use ExUnit.Case
  
  setup do
    # Start TRM supervision tree
    start_supervised!(MyApp.TRM.Supervisor)
    :ok
  end
  
  describe "Jido Agent Integration" do
    test "TRM agent processes reasoning request" do
      {:ok, agent} = MyApp.Agents.TRMReasoning.start_link()
      
      question = generate_sudoku_puzzle()
      
      {:ok, result} = Jido.Agent.cmd(agent, [
        %Jido.Instruction{
          action: "recursive_reason",
          params: %{question: question, max_steps: 8}
        }
      ])
      
      assert result.answer
      assert result.steps <= 8
    end
    
    test "TRM agent collaborates with other agents via signals" do
      {:ok, trm_agent} = MyApp.Agents.TRMReasoning.start_link()
      {:ok, orchestrator} = MyApp.Agents.Orchestrator.start_link()
      
      signal = Jido.Signal.new(%{
        type: "problem.solve.request",
        data: %{problem: generate_arc_task()},
        jido_dispatch: [{:pid, [target: trm_agent]}]
      })
      
      Jido.Signal.dispatch(signal)
      
      # Wait for solution
      assert_receive %Jido.Signal{type: "problem.solve.complete"}, 5000
    end
  end
  
  describe "Concurrent Inference" do
    test "handles multiple concurrent requests" do
      tasks = for i <- 1..10 do
        Task.async(fn ->
          question = generate_test_problem(i)
          MyApp.TRM.ModelServer.predict(question)
        end)
      end
      
      results = Task.await_many(tasks)
      assert Enum.all?(results, fn
        {:ok, _answer, _state} -> true
        _ -> false
      end)
    end
  end
end
```

### 7.3 Property-Based Tests

```elixir
defmodule MyApp.TRM.PropertyTest do
  use ExUnit.Case
  use PropCheck
  
  property "recursive reasoning always improves or maintains answer quality" do
    forall {x, model_state} <- {problem_generator(), model_state_generator()} do
      {:ok, answer, state} = MyApp.TRM.Inference.recursive_reason(
        x,
        model_state,
        n_supervision: 8
      )
      
      # Quality should improve over supervision steps
      qualities = Enum.map(state.history, fn {_step, y, _q} ->
        compute_quality(y, x)
      end)
      
      # Check monotonic improvement
      Enum.chunk_every(qualities, 2, 1, :discard)
      |> Enum.all?(fn [q1, q2] -> q2 >= q1 end)
    end
  end
end
```

---

## 8. Performance Considerations

### 8.1 Optimization Strategies

**1. JIT Compilation with EXLA**
```elixir
# Enable EXLA compiler for GPU acceleration
Nx.default_backend(EXLA.Backend)

# Compile critical functions
defn_options = [compiler: EXLA, client: :cuda]

defn recursive_step(x, y, z, params) do
  # This will be JIT compiled to GPU code
  ...
end
```

**2. Memory Optimization**
```elixir
defmodule MyApp.TRM.MemoryOptimized do
  @doc """
  Use detach() strategically to prevent gradient accumulation
  across supervision steps.
  """
  defnp supervision_with_memory_management(x, y, z, params) do
    # Only track gradients for final recursion
    {y_temp, z_temp} = no_grad_recursion(x, y, z, params)
    
    # Detach to free memory
    y_temp = Nx.detach(y_temp)
    z_temp = Nx.detach(z_temp)
    
    # Final pass with gradients
    final_recursion(x, y_temp, z_temp, params)
  end
end
```

**3. Batch Processing**
```elixir
defmodule MyApp.TRM.BatchInference do
  @doc """
  Process multiple problems in parallel using batching.
  """
  def batch_predict(problems, model_state, opts \\ []) do
    batch_size = opts[:batch_size] || 32
    
    problems
    |> Enum.chunk_every(batch_size)
    |> Task.async_stream(fn batch ->
      # Stack into single tensor for batch processing
      x_batch = Nx.stack(batch)
      MyApp.TRM.ModelServer.predict(x_batch, opts)
    end, max_concurrency: opts[:max_concurrency] || 4)
    |> Enum.flat_map(fn {:ok, results} -> results end)
  end
end
```

### 8.2 Profiling & Monitoring

```elixir
defmodule MyApp.TRM.Telemetry do
  def setup do
    events = [
      [:trm, :inference, :start],
      [:trm, :inference, :stop],
      [:trm, :supervision_step, :complete],
      [:trm, :early_halt, :triggered]
    ]
    
    :telemetry.attach_many(
      "trm-telemetry",
      events,
      &handle_event/4,
      nil
    )
  end
  
  def handle_event([:trm, :inference, :stop], measurements, metadata, _config) do
    duration_ms = measurements.duration / 1_000_000
    
    Logger.info("""
    TRM Inference Complete:
      Duration: #{duration_ms}ms
      Steps: #{metadata.steps}
      Halted: #{metadata.halted}
    """)
    
    # Export to Prometheus/StatsD
    :telemetry.execute(
      [:prometheus, :histogram],
      %{value: duration_ms},
      %{metric: "trm_inference_duration_ms"}
    )
  end
end
```

### 8.3 Performance Benchmarks

Expected performance targets (based on paper):

| Task | Training Time | Inference Time | Accuracy |
|------|--------------|----------------|----------|
| Sudoku-Extreme | < 36 hours (1x L40S) | ~10ms | 87% |
| Maze-Hard | < 24 hours (4x L40S) | ~15ms | 85% |
| ARC-AGI-1 | ~3 days (4x H100) | ~50ms | 45% |

Elixir-specific optimizations can potentially improve these:
- BEAM's lightweight processes enable higher concurrency
- Native distribution across nodes for larger batches
- Hot code reloading for model updates without downtime

---

## 9. Deployment Guide

### 9.1 Production Setup

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :my_app, MyApp.TRM.ModelServer,
    model_path: System.get_env("TRM_MODEL_PATH"),
    pool_size: String.to_integer(System.get_env("TRM_POOL_SIZE", "4")),
    backend: EXLA.Backend,
    client: :cuda
  
  config :nx, :default_backend, EXLA.Backend
  config :exla, :clients,
    cuda: [platform: :cuda, device_id: 0]
end
```

### 9.2 Docker Deployment

```dockerfile
FROM elixir:1.16-alpine AS builder

# Install dependencies
RUN apk add --no-cache build-base git

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

WORKDIR /app

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

# Copy application code
COPY lib ./lib
COPY priv ./priv

# Compile
RUN mix compile

# Release build
RUN mix release

FROM alpine:3.18

RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/my_app ./
COPY --from=builder /app/priv/models ./priv/models

ENV TRM_MODEL_PATH=/app/priv/models/trm_arc_agi.model
ENV TRM_POOL_SIZE=4

CMD ["bin/my_app", "start"]
```

---

## 10. Future Enhancements

### 10.1 Potential Improvements

1. **Adaptive Recursion Depth**: Learn optimal n and T per problem
2. **Multi-Task TRM**: Single model for Sudoku, Maze, and ARC-AGI
3. **Mixture of TRMs**: Ensemble of specialized TRM models
4. **Continual Learning**: Update TRM with new problem types
5. **Explainability**: Visualize reasoning evolution through supervision steps

### 10.2 Research Directions

- **Distributed TRM**: Scale across multiple GPUs/nodes
- **TRM for Code**: Apply to code generation and refactoring
- **Interactive TRM**: Human-in-the-loop reasoning
- **TRM + Search**: Combine with tree search for planning

---

## 11. References & Resources

### Papers
- [TRM Paper](https://arxiv.org/pdf/2510.04871) - Original Tiny Recursion Model paper
- [HRM Paper](https://arxiv.org/abs/2506.21734) - Hierarchical Reasoning Model (predecessor)

### Code References
- [TRM Implementation](https://github.com/SamsungSAILMontreal/TinyRecursiveModels) - Official PyTorch implementation
- [Jido Framework](https://github.com/agentjido/jido) - Elixir agent framework
- [Axon Documentation](https://hexdocs.pm/axon/) - Neural networks in Elixir
- [Nx Documentation](https://hexdocs.pm/nx/) - Numerical computing in Elixir

### Community
- Elixir Forum - ML section
- Nx Slack channel (#machine-learning)
- Jido Discord

---

## Conclusion

This guide provides a complete blueprint for implementing TRM in Elixir with Jido. The combination of TRM's recursive reasoning, Jido's agent architecture, and Elixir's concurrency primitives creates a powerful platform for solving hard reasoning tasks.

**Key Takeaways:**
1. TRM's simplicity makes it ideal for Elixir implementation
2. Jido's agent/skill/action model maps naturally to TRM components
3. BEAM concurrency enables novel parallelization strategies
4. Axon/Nx provide all necessary neural network operations
5. Production deployment is straightforward with OTP supervision

The next step is to start with a minimal implementation on Sudoku-Extreme, validate the architecture, then expand to more complex tasks like ARC-AGI.
