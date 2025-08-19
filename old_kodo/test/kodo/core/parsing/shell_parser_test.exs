defmodule Kodo.Core.ShellParserTest do
  use ExUnit.Case, async: true

  alias Kodo.Core.Parsing.{ShellParser, ExecutionPlan}
  alias ExecutionPlan.{Pipeline, Command, Redirection}

  describe "basic commands" do
    test "simple command with no arguments" do
      assert {:ok, plan} = ShellParser.parse("ls")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "ls", args: [], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "command with arguments" do
      assert {:ok, plan} = ShellParser.parse("ls -la")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "ls", args: ["-la"], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "command with multiple arguments" do
      assert {:ok, plan} = ShellParser.parse("echo hello world")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "echo", args: ["hello", "world"], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end
  end

  describe "quoted strings" do
    test "single quoted string preserves content literally" do
      assert {:ok, plan} = ShellParser.parse("echo 'hello world'")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "echo", args: ["hello world"], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "double quoted string with simple content" do
      assert {:ok, plan} = ShellParser.parse(~s(echo "hello world"))

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "echo", args: ["hello world"], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "escaped quotes in double quoted string" do
      assert {:ok, plan} = ShellParser.parse(~s(echo "say \\"hello\\""))

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "echo", args: [~s(say "hello")], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "mixed quote types" do
      assert {:ok, plan} = ShellParser.parse(~s(echo 'single' "double"))

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{name: "echo", args: ["single", "double"], redirections: []}
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end
  end

  describe "pipes" do
    test "simple pipe between two commands" do
      assert {:ok, plan} = ShellParser.parse("ls | grep txt")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{name: "ls", args: [], redirections: []},
                     %Command{name: "grep", args: ["txt"], redirections: []}
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "multiple pipes" do
      assert {:ok, plan} = ShellParser.parse("cat file.txt | grep pattern | wc -l")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{name: "cat", args: ["file.txt"], redirections: []},
                     %Command{name: "grep", args: ["pattern"], redirections: []},
                     %Command{name: "wc", args: ["-l"], redirections: []}
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "pipes with quoted arguments" do
      assert {:ok, plan} = ShellParser.parse(~s(echo "hello | world" | grep hello))

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{name: "echo", args: ["hello | world"], redirections: []},
                     %Command{name: "grep", args: ["hello"], redirections: []}
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end
  end

  describe "redirections" do
    test "output redirection" do
      assert {:ok, plan} = ShellParser.parse("echo hello > output.txt")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{
                       name: "echo",
                       args: ["hello"],
                       redirections: [%Redirection{type: :output, target: "output.txt"}]
                     }
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "append redirection" do
      assert {:ok, plan} = ShellParser.parse("cat file.txt >> log.txt")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{
                       name: "cat",
                       args: ["file.txt"],
                       redirections: [%Redirection{type: :append, target: "log.txt"}]
                     }
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "input redirection" do
      assert {:ok, plan} = ShellParser.parse("grep pattern < input.txt")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{
                       name: "grep",
                       args: ["pattern"],
                       redirections: [%Redirection{type: :input, target: "input.txt"}]
                     }
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "multiple redirections" do
      assert {:ok, plan} = ShellParser.parse("grep pattern < input.txt > output.txt")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{
                       name: "grep",
                       args: ["pattern"],
                       redirections: [
                         %Redirection{type: :input, target: "input.txt"},
                         %Redirection{type: :output, target: "output.txt"}
                       ]
                     }
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end
  end

  describe "control operators" do
    test "AND operator" do
      assert {:ok, plan} = ShellParser.parse("make && make test")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "make", args: [], redirections: []}],
                   background?: false
                 },
                 %Pipeline{
                   commands: [%Command{name: "make", args: ["test"], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: [:and]
             } = plan
    end

    test "OR operator" do
      assert {:ok, plan} = ShellParser.parse("rm file.txt || echo failed")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "rm", args: ["file.txt"], redirections: []}],
                   background?: false
                 },
                 %Pipeline{
                   commands: [%Command{name: "echo", args: ["failed"], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: [:or]
             } = plan
    end

    test "semicolon operator" do
      assert {:ok, plan} = ShellParser.parse("cmd1; cmd2; cmd3")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "cmd1", args: [], redirections: []}],
                   background?: false
                 },
                 %Pipeline{
                   commands: [%Command{name: "cmd2", args: [], redirections: []}],
                   background?: false
                 },
                 %Pipeline{
                   commands: [%Command{name: "cmd3", args: [], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: [:semicolon, :semicolon]
             } = plan
    end

    test "background operator" do
      assert {:ok, plan} = ShellParser.parse("long_process &")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "long_process", args: [], redirections: []}],
                   background?: true
                 }
               ],
               control_ops: [:background]
             } = plan
    end
  end

  describe "complex examples" do
    test "quoted pipes with output redirection" do
      assert {:ok, plan} = ShellParser.parse(~s(echo "a | b" | grep x > f.txt))

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{name: "echo", args: ["a | b"], redirections: []},
                     %Command{
                       name: "grep",
                       args: ["x"],
                       redirections: [%Redirection{type: :output, target: "f.txt"}]
                     }
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "find with pipes and patterns" do
      assert {:ok, plan} = ShellParser.parse("find . -name '*.ex' | grep -l defmodule")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{name: "find", args: [".", "-name", "*.ex"], redirections: []},
                     %Command{name: "grep", args: ["-l", "defmodule"], redirections: []}
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "multiple control operators" do
      assert {:ok, plan} = ShellParser.parse("cmd1 && cmd2 || cmd3; cmd4")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "cmd1", args: [], redirections: []}],
                   background?: false
                 },
                 %Pipeline{
                   commands: [%Command{name: "cmd2", args: [], redirections: []}],
                   background?: false
                 },
                 %Pipeline{
                   commands: [%Command{name: "cmd3", args: [], redirections: []}],
                   background?: false
                 },
                 %Pipeline{
                   commands: [%Command{name: "cmd4", args: [], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: [:and, :or, :semicolon]
             } = plan
    end
  end

  describe "error cases" do
    test "empty input" do
      assert {:ok, plan} = ShellParser.parse("")
      assert %ExecutionPlan{pipelines: [], control_ops: []} = plan
    end

    test "unclosed single quote" do
      assert {:error, _reason} = ShellParser.parse("echo 'unclosed")
    end

    test "unclosed double quote" do
      assert {:error, _reason} = ShellParser.parse(~s(echo "unclosed))
    end

    test "pipe with no following command" do
      assert {:error, _reason} = ShellParser.parse("ls |")
    end

    test "redirection with no target" do
      assert {:error, _reason} = ShellParser.parse("echo >")
    end
  end

  describe "whitespace handling" do
    test "extra whitespace around operators" do
      assert {:ok, plan} = ShellParser.parse("cmd1   |   cmd2")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [
                     %Command{name: "cmd1", args: [], redirections: []},
                     %Command{name: "cmd2", args: [], redirections: []}
                   ],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end

    test "leading and trailing whitespace" do
      assert {:ok, plan} = ShellParser.parse("  echo hello  ")

      assert %ExecutionPlan{
               pipelines: [
                 %Pipeline{
                   commands: [%Command{name: "echo", args: ["hello"], redirections: []}],
                   background?: false
                 }
               ],
               control_ops: []
             } = plan
    end
  end
end
