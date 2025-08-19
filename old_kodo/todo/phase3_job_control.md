# Phase 3: Job Control & Pipeline Execution Engine

## Overview
Implement a JobManager and pipeline execution engine that can handle background processes, job control, and proper stdio piping between commands.

## Tasks

### 1. Create JobManager (`lib/kodo/core/job_manager.ex`)

#### JobManager GenServer
- Maintains registry of active jobs: `%{job_id => %Job{}}`
- Provides job lifecycle management
- Handles job status updates and cleanup
- Implements job control operations (fg, bg, kill)

#### Job Struct
```elixir
defmodule Kodo.Core.Job do
  defstruct [
    :id,              # Unique job identifier
    :pid,             # Process PID or Supervisor PID
    :status,          # :running | :stopped | :completed | :failed
    :command,         # Original command string
    :started_at,      # DateTime
    :completed_at,    # DateTime (when finished)
    :exit_status,     # Integer exit code
    :background?      # Boolean - background job
  ]
end
```

#### JobManager API
```elixir
def start_job(execution_plan, session_id)
def stop_job(job_id)
def kill_job(job_id, signal \\ :sigterm)
def get_job(job_id)
def list_jobs(session_id \\ nil)
def bring_to_foreground(job_id)
def send_to_background(job_id)
def wait_for_job(job_id, timeout \\ :infinity)
```

### 2. Create Pipeline Executor (`lib/kodo/core/pipeline_executor.ex`)

#### Pipeline Execution Strategy
- Each pipeline spawns under a dedicated Supervisor
- Commands in pipeline run as linked Tasks/Ports
- Stdio streams connected via `GenStage` or manual piping
- Handle process cleanup on pipeline completion/failure

#### Execution Flow
1. **Parse ExecutionPlan** → List of pipelines with control operators
2. **For each pipeline**:
   - Spawn `PipelineSupervisor` under `JobManager`
   - Create stdio connections between commands
   - Start all commands in pipeline simultaneously
   - Monitor for completion/failure
3. **Apply control operators** between pipelines (&&, ||, ;)
4. **Handle background execution** (&)

#### Stdio Management
```elixir
defmodule Kodo.Core.StdioManager do
  # Create pipe connections between commands
  def create_pipeline_connections(commands)
  
  # Handle input/output redirections to files
  def setup_redirections(command, redirections)
  
  # Connect command output to next command input
  def pipe_output_to_input(from_pid, to_pid)
end
```

### 3. Update CommandRunner (`lib/kodo/core/command_runner.ex`)

#### Enhanced Command Execution
- Replace simple command execution with pipeline-aware execution
- Delegate to `PipelineExecutor` for complex commands
- Maintain backward compatibility for simple commands
- Add proper exit status handling

#### Command Context Enhancement
```elixir
defmodule Kodo.Core.CommandContext do
  defstruct [
    :session_id,
    :env,
    :working_dir,
    :stdin,           # Input stream
    :stdout,          # Output stream  
    :stderr,          # Error stream
    :job_id,          # Associated job ID
    :background?,     # Background execution flag
    :opts
  ]
end
```

### 4. Create Job Control Commands (`lib/kodo/commands/job_control.ex`)

#### Built-in Commands
```elixir
defmodule Kodo.Commands.JobControl do
  use Kodo.Core.CommandMacro

  defcommand "jobs" do
    @description "List active jobs"
    @usage "jobs [-l]"
    @meta [:builtin, :pure]
    
    def execute(_args, context) do
      # List jobs from JobManager
    end
  end

  defcommand "fg" do
    @description "Bring job to foreground"
    @usage "fg [job_id]"
    @meta [:builtin]
    
    def execute(args, context) do
      # Bring job to foreground
    end
  end

  defcommand "bg" do
    @description "Send job to background"
    @usage "bg [job_id]"
    @meta [:builtin]
    
    def execute(args, context) do
      # Send job to background
    end
  end

  defcommand "kill" do
    @description "Kill a job"
    @usage "kill [-SIGNAL] job_id"
    @meta [:builtin]
    
    def execute(args, context) do
      # Kill specified job
    end
  end
end
```

### 5. Process Management (`lib/kodo/core/process_manager.ex`)

#### Signal Handling
- Handle SIGINT (Ctrl+C) → interrupt current job
- Handle SIGTSTP (Ctrl+Z) → suspend current job
- Propagate signals to job process groups
- Implement job suspension and resumption

#### Process Groups
```elixir
defmodule Kodo.Core.ProcessGroup do
  # Create process group for job isolation
  def create_group(job_id)
  
  # Add process to group
  def add_to_group(pid, group_id)
  
  # Send signal to entire group
  def signal_group(group_id, signal)
  
  # Clean up process group
  def cleanup_group(group_id)
end
```

### 6. Telemetry Integration (`lib/kodo/telemetry.ex`)

#### Job Events
```elixir
# Job lifecycle events
:telemetry.execute([:kodo, :job, :started], %{count: 1}, %{job_id: id, command: cmd})
:telemetry.execute([:kodo, :job, :completed], %{duration: ms}, %{job_id: id, exit_status: status})
:telemetry.execute([:kodo, :job, :failed], %{count: 1}, %{job_id: id, reason: reason})

# Pipeline events  
:telemetry.execute([:kodo, :pipeline, :started], %{command_count: n}, %{pipeline_id: id})
:telemetry.execute([:kodo, :pipeline, :completed], %{duration: ms}, %{pipeline_id: id})
```

### 7. Testing (`test/kodo/core/`)

#### JobManager Tests (`job_manager_test.exs`)
- Job creation and lifecycle management
- Job status tracking and updates
- Job control operations (start, stop, kill)
- Concurrent job handling
- Job cleanup and resource management

#### PipelineExecutor Tests (`pipeline_executor_test.exs`)
- Simple command execution
- Multi-command pipelines
- Stdio piping between commands
- Input/output redirection to files
- Background job execution
- Error handling and cleanup

#### Integration Tests (`job_control_integration_test.exs`)
- End-to-end pipeline execution
- Job control command functionality
- Signal handling and process management
- Resource cleanup on job termination
- Stress testing with many concurrent jobs

#### Test Scenarios
```elixir
# Simple pipeline
"ls | grep .ex" 

# Background job
"find / -name '*.log' 2>/dev/null &"

# Complex pipeline with redirection
"ps aux | grep beam | awk '{print $2}' > pids.txt"

# Job control
"long_running_task &" -> get job_id -> "kill <job_id>"

# Control operators
"make clean && make build || echo 'Build failed'"
```

### 8. Update Application Supervision (`lib/kodo/application.ex`)

#### Add JobManager to Supervision Tree
```elixir
children = [
  Kodo.Core.Registry,
  Kodo.Core.SessionSupervisor,
  Kodo.Core.VFS.Supervisor,
  {Kodo.Core.JobManager, []},           # Add JobManager
  Kodo.Telemetry
]
```

### 9. Error Handling & Recovery

#### Failure Scenarios
- Command not found in pipeline
- Process crashes during execution
- Pipe connection failures
- Resource exhaustion (too many jobs)
- Signal handling errors

#### Recovery Strategies
- Graceful pipeline termination on command failure
- Automatic cleanup of zombie processes
- Resource limit enforcement
- Error reporting to user with helpful messages

## Success Criteria
- [ ] Background jobs execute properly with `&`
- [ ] Pipelines connect stdio between commands correctly
- [ ] Job control commands work (jobs, fg, bg, kill)
- [ ] Control operators (&&, ||, ;) function correctly
- [ ] Signal handling works (Ctrl+C, Ctrl+Z)
- [ ] Resource cleanup prevents zombie processes
- [ ] All tests pass with >90% coverage
- [ ] Performance suitable for interactive shell use

## Example Usage
```elixir
# Start background job
iex> Kodo.Shell.eval(session, "find / -name '*.log' &")
{:ok, "Job started: 1"}

# List jobs
iex> Kodo.Shell.eval(session, "jobs")
{:ok, "[1] Running    find / -name '*.log'"}

# Kill job
iex> Kodo.Shell.eval(session, "kill 1")
{:ok, "Job 1 terminated"}

# Pipeline with redirection
iex> Kodo.Shell.eval(session, "ps aux | grep beam > processes.txt")
{:ok, ""}
```

## Dependencies
- `GenStage` for stream processing (add to mix.exs)
- Existing `Kodo.Core` modules
- System process management capabilities

## Estimated Time
2-3 weeks for implementation and testing
