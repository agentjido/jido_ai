<Plan>
1. **Overview**  
   - We will expand the existing Sparq parser to handle the new `say` command and confirm it is recognized as a special command referencing a module-based action (like a JITO action).  
   - We will also ensure that whitespace and comments are preserved so that we can reconstruct the original source from the AST (lossless parsing).  
   - We will build tests first (test-driven approach), verifying incremental parsing and evaluation steps. 

2. **Initial Test for Parsing Hello World**  
   - **Goal**: Confirm we can parse the Hello World script into an AST without losing whitespace.  
   - **Procedure**:  
     1. **Write a new test** in `test/integration/hello_world_test.exs` (or similar) that:  
        - Loads the Hello World script from a fixture string (with whitespace, newlines, etc. intact).  
        - Parses it into an AST.  
        - Converts the AST back to source code.  
        - Asserts that the resulting source code is identical (whitespace included) to the original.  
     2. **Expected Failure**: The new parser rules for `say` (and possibly for scene and character blocks) do not yet exist, so the test will fail.  

3. **Implement Minimal Parsing for Characters & Scenes**  
   - **Goal**: Provide just enough parsing rules to recognize `character` and `scene` blocks with minimal internal structure.  
   - **Files to Update**:  
     - `lib/sparq/parser.ex` – Add new combinators or references for `character` and `scene` tokens.  
     - `lib/sparq/parser/core.ex` (and possibly other submodules) – Introduce placeholders or basic grammar for top-level constructs:  
       - Example: `character ... do ... end`, `scene ... do ... end`.  
     - Ensure these preserve whitespace tokens as distinct tokens in the AST.  
   - **Incremental Testing**:  
     1. Rerun the Hello World test: it will likely fail on the `beat` block or on commands like `speak` or `say`.  

4. **Add Parsing Support for Beats and Commands**  
   - **Goal**: Gradually expand the parser to handle `beat :start do ... end` and commands like `speak`, `say`, etc.  
   - **Implementation Steps**:  
     1. **Add a combinator** for `beat <identifier> do ... end`.  
     2. **Add command parsing** for `say <Character>`, `speak <Character>`, or other recognized commands.  
     3. **Record whitespace** and store it in the parse tree, so that we can roundtrip.  
     4. **Update** existing tests or create new ones for partial scenes.  
   - **Expectation**: The Hello World test might now parse further, but it will still fail on roundtrip if we don’t handle whitespace properly.  

5. **Lossless Reconstruction**  
   - **Goal**: Ensure each syntactic element captures not only the “meaningful AST” but also the raw textual spans (whitespace, comments).  
   - **Implementation Steps**:  
     1. For every recognized token (keywords, identifiers, parentheses), store the preceding whitespace or comment tokens in the parse node’s metadata.  
     2. Add a roundtrip function (similar to the “unparser”) that re-walks the AST and reconstructs the full text from stored tokens.  
     3. Confirm the Hello World test now passes with exact whitespace.  

6. **Testing the Evaluator Setup**  
   - **Goal**: Show that upon successfully parsing the script, the evaluator can bootstrap the basic data structures for the scene, characters, and commands.  
   - **Implementation Steps**:  
     1. **Create a new test** in `test/integration/hello_world_evaluator_test.exs` that:  
        - Parses the script into AST.  
        - Calls the evaluator (e.g., `Sparq.eval/2`) on that AST.  
        - Asserts that we have a recognized `Greeter` character and a recognized `HelloWorldScene`.  
     2. The evaluator should store `character` and `scene` definitions in `Context.modules` or wherever the architecture tracks them.  
     3. This test will fail initially if the evaluator doesn’t handle new constructs like `scene`, `beat`, `say`, etc.  

7. **Implement “say” Command**  
   - **Goal**: Recognize that `say` is a special command that corresponds to a JITO (Elixir) module call.  
   - **Implementation Steps**:  
     1. **Extend** the parser to parse `say <Character>, "string"` or `say "string"` if no character is specified.  
     2. **Extend** the evaluator so that `{:say, meta, args}` is dispatched to a module call (like `Sparq.Handlers.Jito.say(args, context)`).  
        - The simplest approach might be:  
          ```elixir
          def evaluate({:say, meta, [char, text]}, context) do
            AST.eval_call(:Jito, :say, [char, text], context)
          end
          ```  
        - This is just conceptual. The real implementation depends on your existing function-call logic.  
     3. **Retest** the `hello_world_evaluator_test` to confirm the evaluator processes `say` and logs or prints the “Hello, World!” message.  

8. **Incremental Refinements & Cleanups**  
   - **Add More Tests**: For whitespace preservation around `beat`, `character`, and `scene`. Also test partial scripts with multiple beats.  
   - **Refactor**: If the parser or evaluator code starts to become unwieldy, extract common logic or create helper modules.  
   - **Document**: Update `docs/` or code comments to describe the new grammar, the new AST node shapes, and how the “say” command works.  

9. **Key Architectural Considerations**  
   - **Parser & Roundtrip**: The parser must produce a “token-based” AST or store enough metadata to precisely reproduce the original text.  
   - **Evaluator**: As more commands appear, decide if you want a “dispatcher approach” or a “handler registry approach” for each special command.  
   - **Testing Strategy**: Keep each test small and focused on one new feature. Once a test passes, add a new test for the next feature.  

10. **Outcome**  
   - By following these steps incrementally, you will:  
     1. Write failing parser tests for new language constructs (character, scene, beat, say).  
     2. Implement minimal code to pass each test.  
     3. Extend the evaluator to handle “say” as a JITO pass-through command.  
     4. Confirm everything works end-to-end with the Hello World example.  

</Plan>