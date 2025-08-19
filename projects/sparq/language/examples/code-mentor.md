# Code Mentor Example

This example demonstrates a junior developer assistance system using Sparq's concurrent code analysis and interactive debugging features.

## Character Definitions

```sparq
character CodeMentor do
  @name "Code Mentor"
  @goal "Guide junior developers through coding challenges and best practices"
  @backstory """
  An experienced software engineer with a passion for teaching,
  focused on helping developers understand concepts and improve their skills.
  """
end

character CodeAnalyst do
  @name "Code Analyst"
  @goal "Analyze code quality and identify improvement opportunities"
  @backstory "Expert in code analysis and best practices"
end

character DebugHelper do
  @name "Debug Helper"
  @goal "Assist with debugging and problem-solving"
  @backstory "Specialized in debugging techniques and error resolution"
end
```

## Code Review Scene

```sparq
scene CodeReview do
  @title "Code Review Session"
  @characters [CodeMentor, CodeAnalyst, DebugHelper]
  
  beat :start do
    speak CodeMentor, "Let's review your code and identify areas for improvement."
    
    response = ask UserCharacter, "What specific aspects would you like to focus on?"
    
    listen response do
      when match("* performance *") do
        speak CodeMentor, "We'll analyze performance optimization opportunities."
        transition :performance_review
      end
      
      when match("* clean * code *") do
        speak CodeMentor, "Let's focus on code organization and readability."
        transition :clean_code_review
      end
      
      when match("* bug *") do
        speak CodeMentor, "We'll help you track down and fix that bug."
        transition :debug_session
      end
      
      # Default response
      speak CodeMentor, "Let's start with a general code review."
      transition :general_review
    end
  end
  
  beat :general_review do
    speak CodeMentor, "I'll coordinate with our team to analyze different aspects of your code."
    
    parallel do
      direct CodeAnalyst, :analyze_code_quality, async: true
      direct DebugHelper, :check_error_patterns, async: true
      direct CodeMentor, :review_architecture, async: true
    end
    
    speak CodeMentor, "Analyzing your code..."
    transition :review_findings
  end
  
  beat :review_findings do
    quality_report = wait CodeAnalyst
    error_patterns = wait DebugHelper
    architecture_review = wait CodeMentor
    
    speak CodeMentor, "Here's what we've found in your code:"
    speak CodeAnalyst, "Code quality insights: #{quality_report}"
    speak DebugHelper, "Potential issues: #{error_patterns}"
    
    response = ask UserCharacter, "Would you like to address any of these findings?"
    
    listen response do
      when match("* fix * issues *") do
        speak CodeMentor, "Let's work on fixing these issues together."
        transition :fix_issues
      end
      
      when match("* explain *") do
        speak CodeMentor, "I'll explain each finding in detail."
        transition :explain_findings
      end
      
      # Default response
      speak CodeMentor, "Let's prioritize these improvements together."
      transition :prioritize_changes
    end
  end
end
```

## Code Analysis Flow

```sparq
flow CodeQualityAnalysis do
  @character CodeAnalyst
  @goal "Analyze code quality and suggest improvements"
  
  step :analyze_structure do
    when has_source_code?() do
      analyze_code_structure()
    end
  end
  
  step :check_patterns do
    direct CodeMentor, :get_best_practices, async: true
    analyze_code_patterns()
  end
  
  step :generate_recommendations do
    practices = wait CodeMentor
    generate_improvement_suggestions(practices)
  end
end
```

## Development Tools

```sparq
tool CodeAnalyzer do
  @description "Analyzes code quality and structure"
  @input_type :source_code
  @output_type :analysis_report
  
  def run(code, context) do
    case analyze_code(code) do
      {:ok, analysis} -> {:ok, format_code_analysis(analysis)}
      {:error, reason} -> {:error, "Code analysis failed: #{reason}"}
    end
  end
end

tool BugDetector do
  @description "Identifies potential bugs and code smells"
  @input_type :code_segment
  @output_type :issue_report
  
  def run(segment, context) do
    case detect_issues(segment) do
      {:ok, issues} -> {:ok, format_issues(issues)}
      {:error, reason} -> {:error, "Issue detection failed: #{reason}"}
    end
  end
end

tool RefactoringGuide do
  @description "Suggests code refactoring improvements"
  @input_type :code_analysis
  @output_type :refactoring_suggestions
  
  def run(analysis, context) do
    case generate_suggestions(analysis) do
      {:ok, suggestions} -> {:ok, format_suggestions(suggestions)}
      {:error, reason} -> {:error, "Suggestion generation failed: #{reason}"}
    end
  end
end
```

## Debugging Session Scene

```sparq
scene DebugSession do
  @title "Interactive Debugging"
  @characters [CodeMentor, DebugHelper]
  
  beat :start do
    speak CodeMentor, "Let's work through this bug together."
    
    parallel do
      direct DebugHelper, :analyze_stack_trace, async: true
      direct CodeMentor, :review_context, async: true
    end
    
    speak CodeMentor, "Analyzing the error..."
    transition :analyze_error
  end
  
  beat :analyze_error do
    stack_analysis = wait DebugHelper
    context_review = wait CodeMentor
    
    speak CodeMentor, "Here's what we've found:"
    speak DebugHelper, "Error analysis: #{stack_analysis}"
    
    response = ask UserCharacter, "Would you like to see the suggested fix?"
    
    listen response do
      when match("* yes * show *") do
        speak CodeMentor, "Here's how we can fix this issue."
        transition :explain_fix
      end
      
      when match("* help * understand *") do
        speak CodeMentor, "Let's break down what's happening."
        transition :explain_error
      end
      
      # Default response
      speak CodeMentor, "Let's step through this together."
      transition :step_through
    end
  end
end
```

This example demonstrates:
1. Multi-character code review coordination
2. Parallel processing of code analysis
3. Sophisticated input handling for development queries
4. Integration of specialized development tools
5. Interactive debugging assistance 