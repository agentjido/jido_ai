# Run each Elixir cell in an isolated VM, in notebook order.
# Usage: elixir guides/livebooks/verify.exs guides/livebooks/name.livemd
[path] = System.argv()
source = File.read!(path)
cells = Regex.scan(~r/^```elixir\n(.*?)^```/ms, source, capture: :all_but_first)

if cells == [], do: raise("No Elixir cells in #{path}")

Enum.reduce(Enum.with_index(cells, 1), [], fn {[code], index}, binding ->
  try do
    {_result, next_binding} = Code.eval_string(code, binding, file: path, line: 1)
    IO.puts("cell #{index}: ok")
    next_binding
  rescue
    error ->
      IO.puts(:stderr, "cell #{index}: #{Exception.format(:error, error, __STACKTRACE__)}")
      System.halt(1)
  end
end)
