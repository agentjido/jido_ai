defmodule Sparq.Handlers.RegistryTest do
  use ExUnit.Case, async: true
  alias Sparq.Handlers.Registry

  describe "get_handler/1" do
    test "returns Builtins for arithmetic operations" do
      arithmetic_ops = [:+, :-, :*, :/]

      for op <- arithmetic_ops do
        assert Registry.get_handler(op) == Sparq.Handlers.Builtins
      end
    end

    test "returns IO for print operation" do
      assert Registry.get_handler(:print) == Sparq.Handlers.IO
    end

    test "returns Variables for bind operation" do
      assert Registry.get_handler(:bind) == Sparq.Handlers.Variables
    end

    test "returns Types for type operations" do
      type_ops = [
        :string,
        :string_concat,
        :atom,
        :atom_to_string,
        :list,
        :cons,
        :head,
        :tail,
        :empty?,
        :map,
        :map_put,
        :map_get,
        :map_delete,
        true,
        false,
        :and,
        :or,
        :not,
        nil,
        :nil?,
        :type_of
      ]

      for op <- type_ops do
        assert Registry.get_handler(op) == Sparq.Handlers.Types
      end
    end

    test "returns Kernel for process and system operations" do
      kernel_ops = [
        :node,
        :self,
        :spawn,
        :spawn_link,
        :send,
        :process_info,
        :process_flag,
        :make_ref,
        :monitor,
        :demonitor,
        :is_pid,
        :is_reference,
        :is_port,
        :is_tuple,
        :tuple_size,
        :elem,
        :put_elem,
        :system_time,
        :monotonic_time
      ]

      for op <- kernel_ops do
        assert Registry.get_handler(op) == Sparq.Handlers.Kernel
      end
    end

    test "returns module when given a module name" do
      assert Registry.get_handler(Enum) == Enum
      assert Registry.get_handler(String) == String
    end

    test "raises error for unknown operation" do
      assert_raise ArgumentError, ~s(No handler found for operation: "unknown"), fn ->
        Registry.get_handler("unknown")
      end
    end
  end
end
