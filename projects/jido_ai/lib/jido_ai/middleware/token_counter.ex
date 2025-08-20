defmodule Jido.AI.Middleware.TokenCounter do
  @moduledoc """
  Middleware for counting tokens in AI requests and responses.

  Automatically tracks token usage by counting tokens in the request phase
  and response phase, storing the results in the context metadata.

  ## Metadata Keys

    * `:request_tokens` - Number of tokens in the request
    * `:response_tokens` - Number of tokens in the response

  ## Usage

      middlewares = [Jido.AI.Middleware.TokenCounter]
      context = Middleware.run(middlewares, context, &api_call/1)
      
      request_tokens = Context.get_meta(context, :request_tokens)
      response_tokens = Context.get_meta(context, :response_tokens)

  ## Examples

      # Request phase - counts tokens in request body
      context = %Context{phase: :request, body: %{"messages" => [...]}}
      context = TokenCounter.call(context, next)
      # context.meta.request_tokens now contains the token count

      # Response phase - counts tokens in response body  
      context = %Context{phase: :response, body: %{"choices" => [...]}}
      context = TokenCounter.call(context, next)
      # context.meta.response_tokens now contains the token count
  """

  @behaviour Jido.AI.Middleware

  alias Jido.AI.{Middleware.Context, TokenCounter}

  @doc """
  Processes the context and counts tokens based on the current phase.

  In the request phase, counts tokens in the request body and stores in
  `context.meta.request_tokens`.

  In the response phase, counts tokens in the response body and stores in
  `context.meta.response_tokens`.

  ## Parameters

    * `context` - The current context flowing through the pipeline
    * `next` - Function to call the next middleware in the chain

  ## Returns

  The context with token counts added to the metadata.
  """
  @spec call(Context.t(), (Context.t() -> Context.t())) :: Context.t()
  def call(context, next) do
    # Count request tokens and store in metadata (request phase)
    request_tokens = TokenCounter.count_request_tokens(context.body)
    context = Context.put_meta(context, :request_tokens, request_tokens)

    # Call next middleware/final function (this switches to response phase)
    context = next.(context)

    # Count response tokens and store in metadata (response phase)
    response_tokens = TokenCounter.count_response_tokens(context.body)
    Context.put_meta(context, :response_tokens, response_tokens)
  end
end
