Below is a rough, high-level plan for refactoring the scoping system to be simpler and more consistent, especially around block vs. module scopes, the concept of a “script” node vs. “block” node, and how functions and modules store their data. The plan also outlines how you can incorporate tail call optimization (TCO) to improve performance.

1. Unify or Clarify Script vs. Block
	1.	Decision:
	•	Option B: Keep them separate if you truly need a distinction in behavior—but define them more simply. For example:
	•	{:script, meta, body} can be an entry point for your interpreter.
	•	{:block, meta, exprs} is used for child blocks.
	2.	Implementation Steps:
	•	If you unify them, replace any {:script, …} references with {:block, …}, ensuring your top-level code still gets executed in sequence.
	•	Update the evaluator logic so that it no longer has a special branch for “script.”
	•	If you do keep “script” for clarity, confirm that it’s basically “just a block” with a different name—so the logic is shared.

2. Simplify Module Definition Rules
	1.	Decide Where Modules Can Be Defined:
	•	Recommendation: Restrict modules to be defined only in two places:
	1.	Top-Level (a “global” scope or “script” scope)
	2.	Inside Another Module (namespaced in that module).
This eliminates the complexity of module definitions within functions or ephemeral blocks. It also mirrors typical languages (e.g., Elixir or Python modules).
	2.	Namespacing / Hierarchy:
	•	If you allow “module in a module,” define a straightforward hierarchical naming scheme (e.g. if you define module :Foo inside module :Bar, then it’s accessible as Bar.Foo).
	3.	Implementation Steps:
	•	In your evaluator, when you see {:module, meta, body}, check whether context.current_frame.type is either :root (top-level) or :module (nesting). Raise an error otherwise.
	•	Simplify how you store a child module:
	•	If in a module, it becomes ParentModule.ChildModule.
	•	If in top-level, it’s just ChildModule.

3. Keep Module Variables and Module Functions Separate
	1.	Current Situation: You merge all “module state” (variables) and “function closures” into a single map, which can complicate logic.
	2.	Recommendation:
	•	Keep two separate maps in the module frame:
	1.	Functions: A map of function names to function closures.
	2.	State (variables): A map of key => value for any “global” or “module-level” data.
	•	This makes it clearer when you’re reading or writing a “module global variable” vs. looking up a “module function.”
	3.	Implementation Steps:
	•	In the Sparq.Frame or in the “module object,” define something like:

%{
  type: :module,
  name: mod_name,
  functions: %{},
  state: %{},    # or :variables
  # ...
}


	•	When you define a function inside a module, store it in functions[name].
	•	When you bind a variable at module scope, store it in state[var_name].

	4.	Impact on Evaluator:
	•	Searching for a function name in a module frame is now: mod_frame.functions[to_string(fun_name)].
	•	Searching for a variable is: mod_frame.state[var_name] (or similar).
	•	This approach drastically reduces confusion in code where you conflate function references with data variables.

4. Revisit Block Frames and Function Frames
	1.	Block Frames:
	•	Each {:block, …} (or “script/block”) currently pushes its own frame. This is powerful if you want truly local variables in each block. But it can also be heavy if you have many nested blocks.
	•	Option: Keep it if you want lexical scoping. Or consider simpler scoping: only functions create a new frame, while blocks share the same scope. (This is a tradeoff—Elixir style scoping vs. simpler DSL style.)
	2.	Function Frames:
	•	Functions definitely need frames—since they hold parameters, local variables, etc.
	•	If you want tail call optimization, you can add a check: if a function calls itself as its last operation, skip the current stack frame’s re-creation. This will reduce stack usage.
	3.	Implementation Steps:
	•	For TCO:
	1.	Detect if the final AST node in a function body is a call to the same function.
	2.	If so, rebind the arguments, update the context, and jump back to the top of that function’s evaluation without pushing/popping frames.
	3.	(Or, do a direct loop in the evaluator if the call is to the same function: effectively a “goto” to the top of that function’s body.)
	•	For simpler block frames:
	•	If you want to keep them, fine. If not, you can keep a single “function scope frame” around but unify block-scope variables with it. This is more “dynamic scope” than “lexical scope,” so just be aware of the tradeoff.

5. Performance Considerations & Tail Call Optimization
	1.	TCO (Tail Call Optimization) is especially relevant if you allow recursion.
	2.	Implementation:
	•	A typical approach in an AST-based interpreter is to detect a pattern like {:call, _, [self_function, …args]} as the last expression in a function body.
	•	If the function name matches the current function’s name, and if it’s truly the last AST node, you can skip popping/pushing a new frame and effectively loop with updated arguments.
	•	Watch out for cases with side effects or debug mode, as skipping frames might skip some logging. You can decide how to handle it gracefully.
	3.	Block vs. TCO:
	•	If your language allows multi-expression bodies, be sure that a tail call is the last expression, i.e., that no other expression comes after it. If something does come after it, it’s not a tail position.

6. Summary of the Refactoring Plan

Putting it all together:
	1.	Consolidate the “script” node and “block” node into one concept if possible—{:block, meta, exprs}—and let the top-level code just be a block. This reduces AST overhead in the evaluator.
	2.	Restrict where modules can be defined (top-level or inside another module). Prohibit them in function bodies for simplicity.
	3.	Separate a module’s “functions” map from its “state” map so it’s clear when you’re calling a function vs. reading/writing module-level data.
	4.	Consider how many frames you truly need:
	•	Keep a frame for each function invocation.
	•	Possibly unify block scopes with the current frame to reduce overhead, or keep them separate if you prefer strict lexical scoping.
	5.	Implement Tail Call Optimization inside your evaluator:
	•	When evaluating a function, check if the last expression is a call to the same function with new args.
	•	If so, avoid the push/pop frame and rewrite the arguments in place, effectively looping.

These changes will simplify the language architecture, reduce potential confusion about scoping rules, and improve performance by avoiding unnecessary frames, especially once TCO is in place.

Next Steps
	1.	Update the AST: Decide if you’re removing {:script, …} in favor of {:block, …}.
	2.	Rewrite the Evaluator to handle modules only when current_frame is :root or :module.
	3.	Refactor your “module frames” or “module objects” to store functions and state separately.
	4.	Add TCO: Insert logic at the end of function evaluation to see if you’re calling the same function.
	5.	Test: You’ll likely have to rewrite or adapt many tests, especially those that previously relied on the more lenient scoping rules. Add tests that confirm TCO is working (like factorial calls that do not blow the stack).

Following this plan should yield simpler scoping and a more direct mental model of how your language’s modules, blocks, and functions coexist—while also giving you some performance wins.