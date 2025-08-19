defmodule JidoTest.Helpers.Assertions do
  @moduledoc false
  import ExUnit.Assertions

  @doc """
  Asserts that a module implements a specified behaviour.

  ## Examples

      assert_implements(MyModule, GenServer)
  """
  def assert_implements(module, behaviour) do
    all = Keyword.take(module.__info__(:attributes), [:behaviour])

    assert [behaviour] in Keyword.values(all)
  end

  @doc """
  Partially adapted from Thomas Millar's wait_for
  https://gist.github.com/thmsmlr/8b32cc702acb48f39e653afc0902374f

  This will assert continously for the :check_interval until the :timeout
  has been reached.

  NOTE: In general, it is preferable to wait for some signal like a telemetry
  event or message, but sometimes this is just easier.
  """
  defmacro assert_eventually(assertion, opts \\ []) do
    quote do
      JidoTest.Helpers.Assertions.wait_for(
        fn ->
          assert unquote(assertion)
        end,
        unquote(opts)
      )
    end
  end

  def wait_for(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 100)
    check_interval = Keyword.get(opts, :check_interval, 10)

    start_time = System.monotonic_time(:millisecond)
    ref = make_ref()

    try do
      do_wait_for(fun, start_time, timeout, ref, check_interval)
    catch
      {:wait_for_timeout, ^ref, last_error} ->
        message = """
        Assertion did not succeed within #{timeout}ms.
        Last failure:
        #{Exception.format(:error, last_error, [])}
        """

        flunk(message)
    end
  end

  defp do_wait_for(fun, start_time, timeout, ref, check_interval) do
    fun.()
    :ok
  rescue
    error in [ExUnit.AssertionError] ->
      current_time = System.monotonic_time(:millisecond)

      if current_time - start_time < timeout do
        Process.sleep(check_interval)
        do_wait_for(fun, start_time, timeout, ref, check_interval)
      else
        throw({:wait_for_timeout, ref, error})
      end
  end
end
