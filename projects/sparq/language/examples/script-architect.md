# Script Architect Example

This example demonstrates a meta-agent script building system using Sparq's concurrent script analysis and template generation features.

## Character Definitions

```sparq
character ScriptArchitect do
  @name "Script Architect"
  @goal "Guide users in creating effective Sparq agent scripts"
  @backstory """
  An expert in the Sparq DSL and agent design patterns,
  focused on helping users create well-structured and maintainable agent scripts.
  """
end

character TemplateDesigner do
  @name "Template Designer"
  @goal "Create and customize script templates"
  @backstory "Specialized in script patterns and best practices"
end

character ValidationExpert do
  @name "Validation Expert"
  @goal "Ensure script correctness and completeness"
  @backstory "Expert in script validation and quality assurance"
end
```

## Script Planning Scene

```sparq
scene ScriptPlanning do
  @title "Agent Script Creation"
  @characters [ScriptArchitect, TemplateDesigner, ValidationExpert]
  
  beat :start do
    speak ScriptArchitect, "Let's create your Sparq agent script."
    
    response = ask UserCharacter, "What type of agent would you like to create?"
    
    listen response do
      when match("* customer * support *") do
        speak ScriptArchitect, "We'll create a customer support agent."
        transition :support_agent
      end
      
      when match("* technical * expert *") do
        speak ScriptArchitect, "Let's design a technical expert agent."
        transition :technical_agent
      end
      
      when match("* creative * assistant *") do
        speak ScriptArchitect, "We'll build a creative assistant agent."
        transition :creative_agent
      end
      
      # Default response
      speak ScriptArchitect, "Let's start with a basic agent template."
      transition :basic_agent
    end
  end
  
  beat :basic_agent do
    speak ScriptArchitect, "I'll coordinate with our team to create your agent script."
    
    parallel do
      direct TemplateDesigner, :generate_template, async: true
      direct ValidationExpert, :prepare_checklist, async: true
      direct ScriptArchitect, :analyze_requirements, async: true
    end
    
    speak ScriptArchitect, "Preparing your agent structure..."
    transition :review_template
  end
  
  beat :review_template do
    template = wait TemplateDesigner
    checklist = wait ValidationExpert
    requirements = wait ScriptArchitect
    
    speak ScriptArchitect, "Here's what we've prepared:"
    speak TemplateDesigner, "Script template: #{template}"
    speak ValidationExpert, "Quality checklist: #{checklist}"
    
    response = ask UserCharacter, "Would you like to customize any aspects?"
    
    listen response do
      when match("* personality *") do
        speak ScriptArchitect, "Let's define the agent's personality traits."
        transition :customize_personality
      end
      
      when match("* capabilities *") do
        speak ScriptArchitect, "We'll adjust the agent's capabilities."
        transition :define_capabilities
      end
      
      # Default response
      speak ScriptArchitect, "Let's review the template in detail."
      transition :detailed_review
    end
  end
end
```

## Script Analysis Flow

```sparq
flow ScriptValidation do
  @character ValidationExpert
  @goal "Validate script structure and completeness"
  
  step :check_structure do
    when has_script_draft?() do
      validate_script_structure()
    end
  end
  
  step :analyze_components do
    direct ScriptArchitect, :get_requirements, async: true
    check_component_coverage()
  end
  
  step :generate_report do
    requirements = wait ScriptArchitect
    compile_validation_report(requirements)
  end
end
```

## Script Building Tools

```sparq
tool TemplateGenerator do
  @description "Generates script templates based on requirements"
  @input_type :agent_requirements
  @output_type :script_template
  
  def run(requirements, context) do
    case generate_template(requirements) do
      {:ok, template} -> {:ok, format_template(template)}
      {:error, reason} -> {:error, "Template generation failed: #{reason}"}
    end
  end
end

tool ScriptValidator do
  @description "Validates script structure and completeness"
  @input_type :script_draft
  @output_type :validation_report
  
  def run(draft, context) do
    case validate_script(draft) do
      {:ok, report} -> {:ok, format_validation_report(report)}
      {:error, reason} -> {:error, "Script validation failed: #{reason}"}
    end
  end
end

tool ComponentGenerator do
  @description "Generates script components (scenes, flows, tools)"
  @input_type :component_spec
  @output_type :component_code
  
  def run(spec, context) do
    case generate_component(spec) do
      {:ok, code} -> {:ok, format_component_code(code)}
      {:error, reason} -> {:error, "Component generation failed: #{reason}"}
    end
  end
end
```

## Script Review Scene

```sparq
scene ScriptReview do
  @title "Script Quality Review"
  @characters [ScriptArchitect, ValidationExpert]
  
  beat :start do
    speak ScriptArchitect, "Let's review your script for quality and completeness."
    
    parallel do
      direct ValidationExpert, :run_validation, async: true
      direct ScriptArchitect, :check_best_practices, async: true
    end
    
    speak ScriptArchitect, "Analyzing your script..."
    transition :present_findings
  end
  
  beat :present_findings do
    validation_results = wait ValidationExpert
    practice_review = wait ScriptArchitect
    
    speak ScriptArchitect, "Here's our script analysis:"
    speak ValidationExpert, "Validation results: #{validation_results}"
    
    response = ask UserCharacter, "Would you like to address any of these points?"
    
    listen response do
      when match("* fix * issues *") do
        speak ScriptArchitect, "Let's improve those areas."
        transition :fix_issues
      end
      
      when match("* explain *") do
        speak ScriptArchitect, "I'll explain each point in detail."
        transition :explain_findings
      end
      
      # Default response
      speak ScriptArchitect, "Let's go through the improvements systematically."
      transition :systematic_review
    end
  end
end
```

This example demonstrates:
1. Multi-character script development coordination
2. Parallel processing of script analysis
3. Sophisticated input handling for agent creation
4. Integration of specialized script building tools
5. Interactive script review and validation 