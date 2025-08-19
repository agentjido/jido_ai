# Brand Voice Example

This example demonstrates a social media coordination system using Sparq's concurrent content analysis and engagement monitoring features.

## Character Definitions

```sparq
character BrandVoice do
  @name "Brand Voice"
  @goal "Maintain consistent brand messaging while maximizing engagement"
  @backstory """
  An experienced social media strategist with deep understanding of brand voice,
  focused on creating engaging content that resonates with the target audience.
  """
end

character ContentAnalyst do
  @name "Content Analyst"
  @goal "Analyze content performance and audience engagement"
  @backstory "Expert in social media metrics and trend analysis"
end

character CrisisManager do
  @name "Crisis Manager"
  @goal "Monitor and manage potential PR issues"
  @backstory "Specialized in reputation management and crisis communication"
end
```

## Content Planning Scene

```sparq
scene ContentStrategy do
  @title "Social Media Content Planning"
  @characters [BrandVoice, ContentAnalyst, CrisisManager]
  
  beat :start do
    speak BrandVoice, "Let's plan our social media content strategy."
    
    response = ask UserCharacter, "What are your main content goals?"
    
    listen response do
      when match("* increase * engagement *") do
        speak BrandVoice, "We'll focus on creating more engaging content."
        transition :engagement_strategy
      end
      
      when match("* brand * awareness *") do
        speak BrandVoice, "Let's work on expanding your brand reach."
        transition :awareness_strategy
      end
      
      when match("* sales * conversion *") do
        speak BrandVoice, "We'll create content that drives conversions."
        transition :conversion_strategy
      end
      
      # Default response
      speak BrandVoice, "Let's analyze your current performance first."
      transition :analyze_performance
    end
  end
  
  beat :analyze_performance do
    speak BrandVoice, "I'll coordinate with our team to analyze your social presence."
    
    parallel do
      direct ContentAnalyst, :analyze_metrics, async: true
      direct CrisisManager, :assess_risks, async: true
      direct BrandVoice, :review_content, async: true
    end
    
    speak BrandVoice, "Analyzing your social media performance..."
    transition :review_analysis
  end
  
  beat :review_analysis do
    metrics = wait ContentAnalyst
    risks = wait CrisisManager
    content_review = wait BrandVoice
    
    speak BrandVoice, "Here's what we've found:"
    speak ContentAnalyst, "Performance metrics: #{metrics}"
    speak CrisisManager, "Risk assessment: #{risks}"
    
    response = ask UserCharacter, "Would you like to see our recommended strategy?"
    
    listen response do
      when match("* yes * show *") do
        speak BrandVoice, "Great! Let me present our recommendations."
        transition :present_strategy
      end
      
      when match("* concerns *") do
        speak BrandVoice, "Let's address your concerns first."
        transition :address_concerns
      end
      
      # Default response
      speak BrandVoice, "Let's go through the details together."
      transition :explain_analysis
    end
  end
end
```

## Content Analysis Flow

```sparq
flow ContentAnalysis do
  @character ContentAnalyst
  @goal "Analyze content performance and identify trends"
  
  step :gather_metrics do
    when has_historical_data?() do
      collect_performance_metrics()
    end
  end
  
  step :analyze_trends do
    direct BrandVoice, :get_content_calendar, async: true
    analyze_engagement_patterns()
  end
  
  step :generate_insights do
    calendar = wait BrandVoice
    correlate_performance_data(calendar)
  end
end
```

## Social Media Tools

```sparq
tool EngagementAnalyzer do
  @description "Analyzes social media engagement patterns"
  @input_type :engagement_data
  @output_type :engagement_analysis
  
  def run(data, context) do
    case analyze_engagement(data) do
      {:ok, analysis} -> {:ok, format_engagement_insights(analysis)}
      {:error, reason} -> {:error, "Engagement analysis failed: #{reason}"}
    end
  end
end

tool ContentOptimizer do
  @description "Optimizes content for maximum engagement"
  @input_type :content_draft
  @output_type :optimized_content
  
  def run(draft, context) do
    case optimize_content(draft) do
      {:ok, content} -> {:ok, format_optimized_content(content)}
      {:error, reason} -> {:error, "Content optimization failed: #{reason}"}
    end
  end
end

tool CrisisDetector do
  @description "Monitors for potential PR issues"
  @input_type :social_data
  @output_type :risk_assessment
  
  def run(data, context) do
    case detect_risks(data) do
      {:ok, risks} -> {:ok, format_risk_assessment(risks)}
      {:error, reason} -> {:error, "Risk detection failed: #{reason}"}
    end
  end
end
```

## Crisis Management Scene

```sparq
scene CrisisResponse do
  @title "Social Media Crisis Management"
  @characters [BrandVoice, CrisisManager, ContentAnalyst]
  
  beat :start do
    speak CrisisManager, "We've detected a potential issue that needs attention."
    
    parallel do
      direct ContentAnalyst, :analyze_sentiment, async: true
      direct CrisisManager, :assess_impact, async: true
      direct BrandVoice, :draft_response, async: true
    end
    
    speak CrisisManager, "Analyzing the situation..."
    transition :evaluate_situation
  end
  
  beat :evaluate_situation do
    sentiment = wait ContentAnalyst
    impact = wait CrisisManager
    response_draft = wait BrandVoice
    
    speak CrisisManager, "Here's our situation analysis:"
    speak ContentAnalyst, "Public sentiment: #{sentiment}"
    speak BrandVoice, "Proposed response: #{response_draft}"
    
    response = ask UserCharacter, "Should we proceed with this response?"
    
    listen response do
      when match("* yes * approve *") do
        speak CrisisManager, "We'll implement the response immediately."
        transition :implement_response
      end
      
      when match("* revise *") do
        speak CrisisManager, "We'll revise the response strategy."
        transition :revise_response
      end
      
      # Default response
      speak CrisisManager, "Let's review the options carefully."
      transition :review_options
    end
  end
end
```

This example demonstrates:
1. Multi-character social media coordination
2. Parallel processing of content analytics
3. Sophisticated input handling for content strategy
4. Integration of specialized social media tools
5. Crisis management with real-time response 