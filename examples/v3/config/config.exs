import Config

# HTTP/1 barriers need spare connections in the same pool.
config :req_llm, finch: [name: ReqLLM.Finch, pools: %{default: [size: 8, count: 1]}]
