#!/usr/bin/env elixir

# Quick test script to validate Phase 2 implementation
Mix.install([])

# Add the lib path to Code.path so we can load modules
Code.prepend_path("lib")

# Load the needed modules
Code.require_file("lib/kodo/core/execution_plan.ex")
Code.require_file("lib/kodo/core/shell_parser.ex")

alias Kodo.Core.ShellParser

IO.puts("Testing Phase 2 Parser Implementation...")

# Test simple command
case ShellParser.parse("ls -la") do
  {:ok, plan} ->
    IO.puts("✅ Simple command: #{inspect(plan)}")
  {:error, reason} ->
    IO.puts("❌ Simple command failed: #{reason}")
end

# Test pipe
case ShellParser.parse("ls | grep txt") do
  {:ok, plan} ->
    IO.puts("✅ Pipe command: #{inspect(plan)}")
  {:error, reason} ->
    IO.puts("❌ Pipe command failed: #{reason}")
end

# Test redirection
case ShellParser.parse("echo hello > output.txt") do
  {:ok, plan} ->
    IO.puts("✅ Redirection: #{inspect(plan)}")
  {:error, reason} ->
    IO.puts("❌ Redirection failed: #{reason}")
end

# Test control operators
case ShellParser.parse("make && make test") do
  {:ok, plan} ->
    IO.puts("✅ Control operators: #{inspect(plan)}")
  {:error, reason} ->
    IO.puts("❌ Control operators failed: #{reason}")
end

# Test complex example
case ShellParser.parse("find . -name '*.ex' | grep -l defmodule") do
  {:ok, plan} ->
    IO.puts("✅ Complex command: #{inspect(plan)}")
  {:error, reason} ->
    IO.puts("❌ Complex command failed: #{reason}")
end

IO.puts("\nPhase 2 testing complete!")
