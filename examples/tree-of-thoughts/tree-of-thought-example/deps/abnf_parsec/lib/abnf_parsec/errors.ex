defmodule AbnfParsec.LeftoverTokenError do
  defexception [:message]
end

defmodule AbnfParsec.UnexpectedTokenError do
  defexception [:message]
end
