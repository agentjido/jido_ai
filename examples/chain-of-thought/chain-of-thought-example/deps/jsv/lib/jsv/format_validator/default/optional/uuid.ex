# credo:disable-for-this-file Credo.Check.Refactor.CyclomaticComplexity

defmodule JSV.FormatValidator.Default.Optional.UUID do
  @moduledoc false
  defguard is_hex(n) when n in ?0..?9 or n in ?a..?f or n in ?A..?F

  @doc false
  @spec parse_uuid(binary) :: {:ok, binary} | {:error, :invalid_uuid_format}
  def parse_uuid(
        <<a1, a2, a3, a4, a5, a6, a7, a8, ?-, b1, b2, b3, b4, ?-, c1, c2, c3, c4, ?-, d1, d2, d3, d4, ?-, e1, e2, e3,
          e4, e5, e6, e7, e8, e9, e10, e11, e12>> = data
      )
      when is_hex(a1) and
             is_hex(a2) and
             is_hex(a3) and
             is_hex(a4) and
             is_hex(a5) and
             is_hex(a6) and
             is_hex(a7) and
             is_hex(a8) and
             is_hex(b1) and
             is_hex(b2) and
             is_hex(b3) and
             is_hex(b4) and
             is_hex(c1) and
             is_hex(c2) and
             is_hex(c3) and
             is_hex(c4) and
             is_hex(d1) and
             is_hex(d2) and
             is_hex(d3) and
             is_hex(d4) and
             is_hex(e1) and
             is_hex(e2) and
             is_hex(e3) and
             is_hex(e4) and
             is_hex(e5) and
             is_hex(e6) and
             is_hex(e7) and
             is_hex(e8) and
             is_hex(e9) and
             is_hex(e10) and
             is_hex(e11) and
             is_hex(e12) do
    {:ok, data}
  end

  #
  def parse_uuid(_) do
    {:error, :invalid_uuid_format}
  end
end
