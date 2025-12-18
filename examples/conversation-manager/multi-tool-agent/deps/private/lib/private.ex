defmodule Private do
  @moduledoc File.read!("README.md")

  defmacro __using__(_opts)  do
    quote do
      require Private
      import  Private, only: [ private: 1, private: 2 ]
    end
  end

  
  @doc """
  Define private functions:

      private do
        def ...
        defp ...
      end

  All functions in the block will be defined as public if Mix.env is `:test`, 
  private otherwise.  `def` and `defp` are effectively the same in the block.

  See the documentation for the `Private` module for more information.
  """

  defmacro private(do:  block) do
    quote do
      if Code.ensure_loaded?(Mix) do
        unquote(do_private(block, Mix.env))
      else
        unquote(block)
      end
    end
  end

  @doc false && """
  Define private functions:

      private(env) do
        def ...
        defp ...
      end

  All functions in the block will be defined as public if env is `:test`, 
  private otherwise. This is only provided for my own testing.
  """

  defmacro private(env, do:  block) do
    quote do
      unquote(do_private(block, env))
    end
  end

          
  defp do_private(block, _env = :test) do
    make_defs_public(block)
  end

  defp do_private(block, _env) do
    make_defs_private(block)
  end
  
  
  defp make_defs_private(block) do
    Macro.traverse(block, nil, &make_private/2, &identity/2)
  end

  defp make_defs_public(block) do
    Macro.traverse(block, nil, &make_public/2, &identity/2)
  end

  defp make_private({:def, meta, code}, acc) do
    { {:defp, meta, code}, acc }
  end
  
  defp make_private(ast, acc), do: identity(ast, acc)

  defp make_public({:defp, meta, code}, acc) do
    { {:def, meta, code}, acc }
  end
  
  defp make_public(ast, acc), do: identity(ast, acc)
  
  defp identity(ast, acc) do
    { ast, acc }
  end
end
