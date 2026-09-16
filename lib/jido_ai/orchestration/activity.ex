defmodule Jido.AI.Orchestration.Activity do
  @moduledoc false
  # The session event owner owns these timers. References never enter Agent state.

  def new(job, profile, defaults) do
    idle = profile.controls.idle_timeout

    tool_timeout =
      Enum.reduce(profile.tools, Map.get(defaults, :timeout, 0), &max(&1.timeout, &2))

    automatic = if tool_timeout > 0, do: tool_timeout + 60_000, else: 65_000

    Map.put(job, :activity, %{
      idle_ms: if(idle == 0, do: automatic, else: idle),
      heartbeat_ms: profile.controls.tool_heartbeat,
      tools: MapSet.new(),
      idle: nil,
      heartbeat: nil
    })
  end

  def event(job, kind, data) do
    cond do
      not Map.has_key?(job, :activity) -> job
      Jido.AI.Request.Stream.terminal_kind?(kind) -> stop(job)
      kind == :tool_started -> job |> tool_started(data.tool_call_id) |> touch()
      kind == :tool_completed -> job |> tool_finished(data.tool_call_id) |> touch()
      true -> touch(job)
    end
  end

  def touch(%{activity: %{idle_ms: ms}} = job), do: arm(job, :idle, ms)
  def touch(job), do: job

  defp tool_started(job, id) do
    job = update_in(job.activity.tools, &MapSet.put(&1, id))
    heartbeat(job)
  end

  def tool_finished(%{activity: _} = job, id) do
    job = update_in(job.activity.tools, &MapSet.delete(&1, id))
    if MapSet.size(job.activity.tools) == 0, do: cancel(job, :heartbeat), else: job
  end

  def tool_finished(job, _), do: job

  def heartbeat(%{activity: %{heartbeat_ms: ms, heartbeat: nil, tools: tools}} = job)
      when ms > 0 do
    if MapSet.size(tools) > 0, do: arm(job, :heartbeat, ms), else: job
  end

  def heartbeat(job), do: job

  def current?(%{activity: activity, outcome: nil}, kind, token),
    do: match?(%{token: ^token}, activity[kind])

  def current?(_, _, _), do: false

  def fired(job, kind), do: put_in(job.activity[kind], nil)

  def stop(%{activity: _} = job), do: job |> cancel(:idle) |> cancel(:heartbeat)
  def stop(job), do: job

  defp arm(job, kind, ms) do
    job = cancel(job, kind)
    token = make_ref()
    message = {:ai_activity, job.record.id, job.record.run_id, kind, token}
    timer = Process.send_after(self(), message, ms)
    put_in(job.activity[kind], %{timer: timer, token: token})
  end

  defp cancel(job, kind) do
    if timer = job.activity[kind], do: Process.cancel_timer(timer.timer)
    put_in(job.activity[kind], nil)
  end
end
