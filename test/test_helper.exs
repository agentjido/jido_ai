Mimic.copy(ReqLLM)

ExUnit.start(exclude: [:example, :live])

ExUnit.configure(formatters: Enum.uniq(ExUnit.configuration()[:formatters] ++ [Covenant.Formatter]))
