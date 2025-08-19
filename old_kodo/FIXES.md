### Architectural Critique & Areas for Improvement

Here are the main areas where the architecture could be strengthened.

#### 1. Consolidate the Command Execution Flow

**Observation:** There is a significant ambiguity in how commands are executed.
*   `Kodo.Core.Execution.Executor`: Its docstring states it's a "SIMPLIFIED" engine with the job system disabled. It seems to only handle simple, single built-in commands.
*   `Kodo.Core.Execution.PipelineExecutor`: This appears to be the "real" executor, capable of handling pipelines, backgrounding, and job coordination.
*   `Kodo.Core.Jobs.JobManager`: It uses `PipelineExecutor.exec` within a `Task.async` call to run jobs.
*   `Kodo.Shell` and `Kodo.Transports.IEx`: These use the *simplified* `Executor.exec`.

**Problem:** This split is confusing and leads to feature disparity. A command run via the `IEx` transport (`mix kodo`) will not support pipelines, job control, or external commands, while the underlying system (`JobManager`, `PipelineExecutor`) is clearly designed to. There are disabled tests (`executor_test.exs`, `simple_commands_test.exs`) that indicate a refactoring is incomplete.

**Recommendation:**
1.  **Deprecate and remove the simplified `Kodo.Core.Execution.Executor`**. Its logic is a subset of what `PipelineExecutor` and `JobManager` provide.
2.  Refactor the main entry point for command execution (e.g., a new `Kodo.execute_command/3` function) to *always* go through the `JobManager`. Even foreground commands are just jobs that the shell waits on.
3.  Update `Kodo.Transports.IEx` to use this new, unified entry point. This will make pipelines, redirections, and job control (`&`) available immediately in the interactive shell.
4.  This unification will resolve the disabled job control commands in `instance.ex` and the commented-out tests.

#### 2. Decouple Built-in Commands from Session State

**Observation:** Commands like `Kodo.Commands.Cd` and `Kodo.Commands.Env` directly call `Kodo.Core.Sessions.Session.set_env/3`.

```elixir
// in lib/kodo/commands/cd.ex
defp update_pwd(session_pid, new_path) do
  Kodo.Core.Sessions.Session.set_env(session_pid, "PWD", new_path)
end
```

**Problem:** This creates a tight coupling between the command implementation and the `Session` GenServer. While it works, it violates the "pure function" principle that makes shell commands so powerful. A command should ideally describe *what* should happen, and a higher-level component should be responsible for applying that change to the state. This also makes testing the command logic in isolation more difficult, as it requires a running `Session` process.

**Recommendation:**
Adopt a data-driven return value for commands that modify shell state. Instead of calling the `Session` directly, have them return a data structure describing the desired change.

```elixir
# In lib/kodo/commands/cd.ex
def execute([path], context) do
  new_path = Path.expand(path, context.current_dir)

  case File.dir?(new_path) do
    true ->
      # Instead of calling Session, return a description of the state change
      {:ok, "", %{session_updates: [set_env: %{"PWD" => new_path}]}}
    false ->
      {:error, "Directory does not exist: #{path}"}
  end
end
```
The `PipelineExecutor` or `JobManager` would then be responsible for receiving this result and applying the changes to the session state. This makes commands more reusable and easier to test.

#### 3. Rethink VFS Cross-Filesystem Operations

**Observation:** In `Kodo.VFS.Manager`, cross-filesystem `copy` and `move` operations are implemented by reading the entire file into memory.

```elixir
// in lib/kodo/vfs/manager.ex
case Depot.read(source_fs, source_path) do
  {:ok, content} ->
    case Depot.write(dest_fs, dest_path, content, opts) do
      # ...
```

**Problem:** This is a significant scalability risk. Attempting to copy a multi-gigabyte file would exhaust the BEAM's memory and crash the node.

**Recommendation:**
Use streams for all cross-filesystem operations. `depot` has excellent support for this.

```elixir
# A conceptual fix in lib/kodo/vfs/manager.ex
defp handle_cross_fs_copy(source_fs, source_path, dest_fs, dest_path, _opts) do
  with {:ok, read_stream} <- Depot.stream(source_fs, source_path),
       :ok <- Depot.write_stream(dest_fs, dest_path, read_stream) do
    :ok
  else
    error -> error
  end
end
```
This approach has a minimal memory footprint regardless of file size and is fundamental for a robust VFS layer.