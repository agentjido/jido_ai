ExUnit.start()

# Start the Memory persistence adapter once for all tests
{:ok, _} = Jido.Character.Persistence.Memory.start_link([])

# Configure ExUnit
ExUnit.configure(
  formatters: [ExUnit.CLIFormatter],
  exclude: :pending,
  async: true,
  seed: :os.timestamp() |> elem(2),
  max_cases: System.schedulers_online() * 2
)
