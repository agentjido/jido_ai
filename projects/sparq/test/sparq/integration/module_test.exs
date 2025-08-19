defmodule Sparq.Integration.ModuleTest do
  use SparqTest.ASTCase

  describe "module definitions" do
    test "defines simple module" do
      ast = {:module, [], [{:name, [], [:Test]}, declare(:x, 42)]}
      assert_eval(ast, nil)
    end

    test "defines module with function" do
      ast =
        script([
          {:module, [],
           [
             {:name, [], [:Math]},
             {:function, [], [:add, [:a, :b], {:+, [], [var(:a), var(:b)]}]}
           ]},
          {{:call, [], [:Math, :add]}, [], [2, 3]}
        ])

      assert_eval(ast, 5)
    end

    test "multiple functions in module" do
      ast =
        script([
          {:module, [],
           [
             {:name, [], [:Calculator]},
             {:function, [], [:add, [:a, :b], {:+, [], [var(:a), var(:b)]}]},
             {:function, [], [:multiply, [:a, :b], {:*, [], [var(:a), var(:b)]}]}
           ]},
          declare(:x, {{:call, [], [:Calculator, :add]}, [], [2, 3]}),
          {{:call, [], [:Calculator, :multiply]}, [], [var(:x), 4]}
        ])

      assert_eval(ast, 20)
    end

    @tag :skip
    test "module with internal state" do
      ast =
        script([
          {:module, [],
           [
             {:name, [], [:Counter]},
             declare(:count, 0),
             {:function, [],
              [
                :increment,
                [],
                script([
                  declare(:count, {:+, [], [var(:count), 1]}),
                  var(:count)
                ])
              ]},
             {:function, [], [:get_count, [], var(:count)]}
           ]},
          {{:call, [], [:Counter, :increment]}, [], []},
          {{:call, [], [:Counter, :increment]}, [], []},
          {{:call, [], [:Counter, :get_count]}, [], []}
        ])

      assert_eval(ast, 2)
    end
  end

  describe "module error cases" do
    test "calling undefined module" do
      ast = {{:call, [], [:NonExistent, :func]}, [], []}

      assert_raise RuntimeError, ~r/undefined module/i, fn ->
        eval_ast(ast)
      end
    end

    test "calling undefined function in existing module" do
      ast =
        script([
          {:module, [],
           [
             {:name, [], [:Test]},
             {:function, [], [:func1, [], 1]}
           ]},
          {{:call, [], [:Test, :func2]}, [], []}
        ])

      assert_raise RuntimeError, ~r/undefined function/i, fn ->
        eval_ast(ast)
      end
    end

    test "invalid module name" do
      ast = {:module, [], [{:name, [], ["invalid"]}, declare(:x, 1)]}

      assert_raise RuntimeError, ~r/invalid module name/i, fn ->
        eval_ast(ast)
      end
    end

    test "rejects module definition in function" do
      ast =
        script([
          {:module, [],
           [
             {:name, [], [:Outer]},
             {:function, [],
              [
                :make_module,
                [],
                {:module, [],
                 [
                   {:name, [], [:Inner]},
                   {:function, [], [:value, [], 42]}
                 ]}
              ]}
           ]},
          {{:call, [], [:Outer, :make_module]}, [], []}
        ])

      assert_raise RuntimeError,
                   ~r/modules can only be defined at top-level or inside another module/i,
                   fn ->
                     eval_ast(ast)
                   end
    end

    test "rejects module definition in block" do
      ast =
        script([
          {:block, [],
           [
             {:module, [],
              [
                {:name, [], [:Test]},
                {:function, [], [:value, [], 42]}
              ]}
           ]}
        ])

      assert_raise RuntimeError,
                   ~r/modules can only be defined at top-level or inside another module/i,
                   fn ->
                     eval_ast(ast)
                   end
    end
  end

  describe "module scoping" do
    test "modules don't leak variables" do
      ast =
        script([
          {:module, [],
           [
             {:name, [], [:Test]},
             declare(:internal, 42)
           ]},
          var(:internal)
        ])

      assert_raise RuntimeError, ~r/undefined variable/i, fn ->
        eval_ast(ast)
      end
    end

    @tag :skip
    test "nested module definitions" do
      ast =
        script([
          {:module, [],
           [
             {:name, [], [:Outer]},
             {:module, [],
              [
                {:name, [], [:Inner]},
                {:function, [], [:value, [], 42]}
              ]},
             {:function, [], [:get_inner_value, [], {{:call, [], [:Inner, :value]}, [], []}]}
           ]},
          {{:call, [], [:Outer, :get_inner_value]}, [], []}
        ])

      assert_eval(ast, 42)
    end

    test "nested module is namespaced under parent" do
      ast =
        script([
          {:module, [],
           [
             {:name, [], [:Outer]},
             {:module, [],
              [
                {:name, [], [:Inner]},
                {:function, [], [:value, [], 42]}
              ]}
           ]},
          {{:call, [], [:"Outer.Inner", :value]}, [], []}
        ])

      assert_eval(ast, 42)
    end
  end
end
