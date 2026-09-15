defmodule JidoAI.Examples.ToolLimitsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Request}
  alias JidoAI.Examples.ToolLimits.FixtureAgent, as: Agent
  alias JidoAI.Examples.ToolLimits.{Probe}

  defp call(id, n, name \\ "timed_probe"), do: %{id: id, name: name, arguments: %{n: n}}

  defp request(server, context),
    do:
      Request.create_and_send(server, "Work",
        signal_type: "ai.ask",
        source: "/examples/tool-limits",
        context: context,
        stream_to: self()
      )

  defp context(context),
    do: Map.put(context, :counter, start_supervised!({Elixir.Agent, fn -> %{} end}))

  defp record(server, request), do: Server.agent(server).state.requests[request.id]

  defp source do
    {_, options} = Enum.find(Agent.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    Map.from_struct(options[:profiles].assistant)
  end

  defp base,
    do: %{
      name: "tool_limit_example",
      module: Agent,
      vsn: Agent.vsn(),
      schema: Agent.domain_schema(),
      routes: [{"ai.ask", Authoring.ai(:assistant)}]
    }

  defp start(jido, changes \\ %{}) do
    assert {:ok, definition} = Authoring.lower(base(), [Map.merge(source(), changes)])
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  for mode <- [:error, :interrupt] do
    test "native operation #{mode} stops the batch before tools", %{
      jido: jido
    } do
      {mock, ctx} = mock([%{reply: {:tools, [call("one", 1), call("two", 2)]}}])

      ctx =
        context(ctx)
        |> Map.merge(%{
          native_block: "two",
          native_result: unquote(mode)
        })

      server = start(jido)
      assert {:ok, request} = request(server, ctx)
      assert {:error, reason} = Request.await(request)

      if unquote(mode) == :interrupt,
        do: assert(match?({:interrupt, %{kind: :approval}}, reason)),
        else: assert(reason == :native_blocked)

      refute_receive {:probe_started, _, _, _, _}, 20
      assert record(server, request).status == :failed
      assert_script_done(mock)
    end
  end

  for name <- ["timed_probe", "timed_flow"] do
    @tag history_case: "HIST-08/tool-timeout"
    test "a core timeout kills #{name} and retains its explicit no-retry result", %{jido: jido} do
      {mock, ctx} =
        mock([
          %{reply: {:tools, [call("timeout", 1, unquote(name))]}},
          %{reply: {:text, "Timed out"}}
        ])

      tools =
        Enum.map(source().tools, &Map.merge(&1, %{timeout: 80, max_retries: 3, retry_backoff: 0}))

      server = start(jido, %{tools: tools})
      assert {:ok, request} = request(server, Map.put(context(ctx), :probe_mode, :hold))
      assert_receive {:probe_started, 1, 1, worker, _}, 2_000
      monitor = Process.monitor(worker)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
      assert {:ok, "Timed out"} = Request.await(request)
      refute_receive {:probe_started, 1, 2, _, _}, 20

      assert [
               %{
                 attempts: 1,
                 status: :error,
                 result: {:error, %{type: type, retryable?: false}, []}
               }
             ] = record(server, request).meta.tool_results

      assert type == if(unquote(name) == "timed_flow", do: :flow_timeout, else: :timeout)

      assert_script_done(mock)
    end
  end

  @tag history_case: "HIST-08/tool-timeout"
  test "explicitly retryable tools get a fresh attempt budget within the total request deadline",
       %{
         jido: jido
       } do
    {mock, ctx} = mock([%{reply: {:tools, [call("retry", 1)]}}, %{reply: {:text, "Retried"}}])

    tools =
      Enum.map(
        source().tools,
        &Map.merge(&1, %{timeout: 200, max_retries: 1, retry_backoff: 150})
      )

    server = start(jido, %{tools: tools})
    assert {:ok, request} = request(server, Map.put(context(ctx), :probe_mode, :retry))
    assert_receive {:probe_started, 1, 1, first, _}, 2_000
    monitor = Process.monitor(first)
    assert_receive {:DOWN, ^monitor, :process, ^first, _}, 2_000
    assert_receive {:probe_started, 1, 2, _, _}, 2_000
    assert {:ok, "Retried"} = Request.await(request)

    assert [%{attempts: 2, status: :ok, duration_ms: duration}] =
             record(server, request).meta.tool_results

    assert duration >= 270
    assert_script_done(mock)
  end

  test "the total request deadline stops held tool work before its larger attempt budget", %{
    jido: jido
  } do
    {mock, ctx} = mock([%{reply: {:tools, [call("deadline", 1)]}}])
    server = start(jido, %{controls: Map.put(source().controls, :timeout, 500)})
    assert {:ok, request} = request(server, Map.put(context(ctx), :probe_mode, :hold))
    assert_receive {:probe_started, 1, 1, worker, _}, 2_000
    monitor = Process.monitor(worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert {:error, _} = Request.await(request)
    assert record(server, request).status == :failed
    assert Server.agent(server).state.reply == ""
    refute_receive {:probe_started, 1, 2, _, _}, 20
    assert_script_done(mock)
  end

  test "DSL data Builder and source JSON retain tool timeout and retry settings", %{jido: jido} do
    source = source()
    assert Enum.find(source.tools, &(&1.name == "timed_probe")).max_retries == 1
    assert Enum.find(source.tools, &(&1.name == "timed_probe")).retry_backoff == 150
    refute Map.has_key?(Enum.find(source.tools, &(&1.name == "timed_flow")), :max_retries)
    assert {:ok, definition} = Authoring.lower(base(), [source])
    assert definition == Agent.definition()
    attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()

    registry =
      source
      |> Map.put(:routes, [])
      |> atoms()
      |> Kernel.++(profile_atoms(source))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("models/answer", {:value, source.models.answer.model})

    assert {:ok, document} = Authoring.Codec.encode([source], registry)

    assert {:ok, decoded} =
             Authoring.Codec.decode(base(), Jason.decode!(Jason.encode!(document)), registry)

    assert built == definition
    assert decoded == definition

    {mock, ctx} =
      mock(
        Enum.flat_map(1..4, fn n ->
          [%{reply: {:tools, [call("format-#{n}", n)]}}, %{reply: {:text, "Done"}}]
        end)
      )

    ctx = context(ctx) |> Map.put(:probe_mode, :retry)

    for definition <- [Agent.definition(), definition, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(definition))
      assert {:ok, request} = request(server, ctx)
      assert {:ok, "Done"} = Request.await(request)
      assert [%{attempts: 2, status: :ok}] = record(server, request).meta.tool_results
    end

    assert_script_done(mock)
  end

  test "invalid timeout and retry bounds reject before activation" do
    for changes <- [%{timeout: 0}, %{timeout: -1}, %{max_retries: -1}, %{retry_backoff: -1}] do
      [tool | rest] = source().tools

      assert {:error, %{field: "tools"}} =
               Authoring.lower(base(), [
                 Map.put(source(), :tools, [Map.merge(tool, changes) | rest])
               ])
    end
  end

  defp atoms(%_{}), do: []
  defp atoms(map) when is_map(map), do: Enum.flat_map(map, fn {k, v} -> atoms(k) ++ atoms(v) end)
  defp atoms(list) when is_list(list), do: Enum.flat_map(list, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(atom) when is_atom(atom), do: [atom]
  defp atoms(_), do: []

  @tag timeout: 90_000
  @tag history_case: "HIST-08/long-tool-budget"
  test "named Action and Flow tools and direct Exec survive the old thirty-second inner limit", %{
    jido: jido
  } do
    {mock, ctx} =
      mock([
        %{reply: {:tools, [call("action", 1), call("flow", 2, "timed_flow")]}},
        %{reply: {:text, "Long work done"}}
      ])

    ctx = context(ctx) |> Map.put(:probe_mode, :hold)
    server = start(jido)
    assert {:ok, request} = request(server, ctx)
    direct = Task.async(fn -> Jido.Exec.run(Probe, %{n: 3}, ctx, timeout: 45_000) end)

    workers =
      for n <- [1, 2, 3] do
        assert_receive {:probe_started, ^n, 1, worker, started}, 2_000
        {worker, Process.monitor(worker), started}
      end

    deadline = System.monotonic_time(:millisecond) + 31_100

    for {worker, _, _} <- workers,
        do:
          Process.send_after(
            worker,
            :release,
            max(deadline - System.monotonic_time(:millisecond), 0)
          )

    assert {:ok, %{elapsed_ms: elapsed}} = Task.await(direct, 40_000)
    assert elapsed >= 31_000

    for {worker, monitor, _} <- workers,
        do: assert_receive({:DOWN, ^monitor, :process, ^worker, _}, 2_000)

    assert {:ok, "Long work done"} = Request.await(request, timeout: 10_000)

    assert Enum.all?(record(server, request).meta.tool_results, fn %{result: {:ok, value, []}} ->
             value.elapsed_ms >= 31_000
           end)

    assert length(record(server, request).meta.tool_results) == 2
    assert_script_done(mock)
  end
end
