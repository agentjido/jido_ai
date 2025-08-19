character ScriptArchitect do
  name "Script Design Guide"
  goal "Help users create effective agent scripts using Sparq DSL"
  backstory """
    An experienced conversational AI designer who specializes in 
    translating human intentions into well-structured Sparq scripts.
    Deeply familiar with screenwriting principles and HTN planning.
  """
end

character CodeReviewer do
  name "Technical Validator"
  goal "Ensure scripts follow Sparq best practices and patterns"
  backstory """
    A meticulous code reviewer with extensive experience in DSL design
    and implementation. Focuses on maintainability and robustness.
  """
end

character DocumentationGuide do
  name "Documentation Specialist"
  goal "Provide relevant examples and explain Sparq concepts"
  backstory """
    A knowledgeable technical writer who excels at explaining complex
    concepts through clear examples and relevant documentation.
  """
end

tool ScriptValidator do
  @description "Validate Sparq script structure and syntax"
  @input_type :sparq_script
  @output_type :validation_result
  
  def run(script, context) do
    with {:ok, ast} <- parse_script(script),
         {:ok, _} <- validate_structure(ast),
         {:ok, _} <- check_best_practices(ast) do
      {:ok, %{valid: true, warnings: [], errors: []}}
    else
      {:error, reason} -> {:ok, %{valid: false, errors: [reason]}}
    end
  end
end

tool TemplateGenerator do
  @description "Generate script templates based on use case"
  @input_type :template_request
  @output_type :sparq_template
  
  def run(request, context) do
    template = case request.type do
      :conversation -> generate_conversation_template()
      :task -> generate_task_template()
      :qa -> generate_qa_template()
      _ -> generate_basic_template()
    end
    {:ok, template}
  end
end

tool DocumentationSearch do
  @description "Find relevant documentation and examples"
  @input_type :search_query
  @output_type :doc_results
  
  def run(query, context) do
    results = search_documentation(query)
    {:ok, format_results(results)}
  end
end

```sparq
scene InitialScriptPlanning do
  @title "Begin Script Creation"
  @characters [ScriptArchitect, DocumentationGuide]
  
  beat :start do
    narrate "The Script Architect welcomes you to the script creation process"
    
    speak ScriptArchitect, """
      Welcome! I'll help you create your Sparq agent script. 
      First, let's understand what kind of agent you want to build.
    """
    
    choose do
      option "I have a specific use case in mind", :specific_case
      option "I'd like to see some examples first", :show_examples
      option "I need help understanding Sparq basics", :explain_basics
    end
  end
  
  beat :specific_case do
    speak ScriptArchitect, "Great! Tell me about your agent's main purpose."
    purpose = ask()
    
    speak DocumentationGuide, "I can show some similar examples while we plan."
    examples = DocumentationSearch.run(%{query: purpose}, context)
    
    speak ScriptArchitect, """
      Based on your description, let's start by defining your agent's character.
      This will shape their personality and capabilities.
    """
    
    transition_to CharacterDefinition
  end
  
  beat :show_examples do
    speak DocumentationGuide, """
      I'll show you some popular agent patterns to help inspire your design.
      Here are some examples of different agent types:
    """
    
    show_examples()
    
    choose do
      option "I like this pattern", :adapt_pattern
      option "Show me more examples", :show_examples
      option "Let's create something custom", :specific_case
    end
  end
  
  beat :explain_basics do
    speak DocumentationGuide, """
      Let me walk you through the key concepts in Sparq. 
      We'll start with characters, scenes, and flows.
    """
    
    transition_to SparqBasicsTutorial
  end
end
```

```sparq
flow ValidateScript do
  @character CodeReviewer
  @goal "Ensure script quality and best practices"
  
  step "initial_validation" do
    results = ScriptValidator.run(script, context)
    
    when results.valid do
      proceed_to_best_practices()
    end
    
    when has_fixable_errors?(results) do
      suggest_fixes(results.errors)
    end
    
    report_major_issues(results.errors)
  end
  
  step "check_best_practices" do
    issues = analyze_patterns(script)
    
    when Enum.empty?(issues) do
      congratulate_user()
    end
    
    when has_minor_issues?(issues) do
      suggest_improvements(issues)
    end
    
    recommend_refactoring(issues)
  end
  
  step "final_review" do
    generate_review_report()
    transition_to ReviewResults
  end
end