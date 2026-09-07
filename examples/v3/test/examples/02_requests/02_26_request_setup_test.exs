defmodule JidoAI.Examples.RequestSetupTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias JidoAI.Examples.RequestSetup

  setup do
    previous = Application.fetch_env(:jido_ai, :model_aliases)
    aliases = Application.get_env(:jido_ai, :model_aliases, %{})
    Application.put_env(:jido_ai, :model_aliases, Map.put(aliases, :request_setup_example, MockLLM.model()))

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  for {module, route, streaming?} <- [
        {RequestSetup.NativeStream, "ai.ask", true},
        {RequestSetup.NativeBuffered, "ai.ask", false},
        {RequestSetup.OptionsStream, "ai.react.query", true},
        {RequestSetup.OptionsBuffered, "ai.react.query", false}
      ] do
    @tag history_case: "HIST-01/runtime-routing"
    test "#{module} merges HTTP options and keeps declared model defaults", %{jido: jido} do
      {mock, context} = mock(List.duplicate(%{reply: {:text, "Done"}}, 3))
      server = start_agent(jido, unquote(module).new!())
      before = Server.agent(server).plugins
      observer = self()

      callback = fn request ->
        send(observer, {:http_options, request.options.receive_timeout})
        Req.Request.put_header(request, "x-callback", "first")
      end

      overrides =
        if unquote(streaming?) do
          # ReqLLM streaming owns the Finch adapter. Its HTTP options still
          # merge with the declared headers before the real stream starts.
          [receive_timeout: 5_000]
        else
          [adapter: JidoAI.Examples.ModelOptions.HttpAdapter, finch_private: [example_callback: callback]]
        end

      cases = [
        [llm_opts: %{"temperature" => 0.8}, req_http_options: overrides],
        [llm_opts: %{}, req_http_options: []],
        [req_http_options: [headers: [{"x-declared", "override"}]]]
      ]

      for opts <- cases do
        assert {:ok, request} =
                 Request.create_and_send(
                   server,
                   "Check setup",
                   Keyword.merge(
                     [
                       signal_type: unquote(route),
                       source: "/examples/request_setup",
                       context: context,
                       stream_to: self()
                     ],
                     opts
                   )
                 )

        assert {:ok, "Done"} = Request.await(request)
        events = request |> Request.Stream.events(stream_event_timeout_ms: 2_000) |> Enum.to_list()
        assert Enum.any?(events, &(&1.kind == :llm_delta)) == unquote(streaming?)
        assert Server.agent(server).state.requests[request.id].meta.model_calls == 1
      end

      if unquote(streaming?),
        do: refute_receive({:http_options, _}, 20),
        else: assert_receive({:http_options, 5_000}, 1_000)

      refute_receive {:http_options, _}, 20
      [first, second, third] = MockLLM.report(mock).requests
      assert Enum.map([first, second, third], & &1.headers["x-declared"]) == ["present", "present", "override"]
      assert first.headers["x-callback"] == if(unquote(streaming?), do: nil, else: "first")
      for request <- [second, third], do: refute(Map.has_key?(request.headers, "x-callback"))
      assert Enum.map([first, second, third], & &1.body["temperature"]) == [0.8, 0.3, 0.3]

      assert Enum.all?(
               [first, second, third],
               &(&1.body["max_tokens"] == 73 and &1.body["stream"] == unquote(streaming?))
             )

      assert Server.agent(server).plugins == before
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      assert {:ok, %{live: nil}} = Session.snapshot(server)
      assert_script_done(mock)
    end
  end

  for {module, streaming?} <- [{RequestSetup.TurnStream, true}, {RequestSetup.TurnBuffered, false}] do
    @tag history_case: "HIST-01/runtime-routing"
    test "#{module} uses the same HTTP merge in direct Turn execution", %{jido: jido} do
      {mock, context} = mock(List.duplicate(%{reply: {:text, "Done"}}, 3))
      server = start_agent(jido, unquote(module).new!())
      before = Server.agent(server).plugins
      base = MockLLM.options(mock)

      requests = [
        Keyword.put(base, :temperature, 0.8),
        base,
        Keyword.update!(base, :req_http_options, &Keyword.put(&1, :headers, [{"x-declared", "override"}]))
      ]

      for options <- requests do
        assert {:ok, agent} = ask(server, put_in(context, [:ai, :assistant, :options], options))
        assert agent.state.reply == "Done"
      end

      [first, second, third] = MockLLM.report(mock).requests
      assert Enum.map([first, second, third], & &1.headers["x-declared"]) == ["present", "present", "override"]
      assert Enum.map([first, second, third], & &1.body["temperature"]) == [0.8, 0.3, 0.3]

      assert Enum.all?(
               [first, second, third],
               &(&1.body["max_tokens"] == 73 and &1.body["stream"] == unquote(streaming?))
             )

      assert Server.agent(server).plugins == before
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      assert_script_done(mock)
    end
  end
end
