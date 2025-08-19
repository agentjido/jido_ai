# Wellness Guide Example

This example demonstrates a health coaching interaction using Sparq's concurrent monitoring and adaptive response features.

## Character Definitions

```sparq
character WellnessGuide do
  @name "Wellness Guide"
  @goal "Help users achieve their health and wellness goals safely and effectively"
  @backstory """
  A knowledgeable health coach with expertise in fitness, nutrition, and wellness,
  focused on creating personalized, sustainable health plans.
  """
end

character NutritionExpert do
  @name "Nutrition Expert"
  @goal "Provide detailed nutritional guidance and meal planning support"
  @backstory "Specialized in dietary analysis and nutritional optimization"
end

character FitnessTrainer do
  @name "Fitness Trainer"
  @goal "Design and adapt exercise programs for optimal results"
  @backstory "Expert in exercise form, progression, and safety"
end
```

## Initial Assessment Scene

```sparq
scene InitialAssessment do
  @title "Wellness Journey Beginning"
  @characters [WellnessGuide, NutritionExpert, FitnessTrainer]
  
  beat :start do
    speak WellnessGuide, "Welcome! I'm here to help you on your wellness journey."
    
    response = ask UserCharacter, "What are your main health goals?"
    
    listen response do
      when match("* weight * loss *") do
        speak WellnessGuide, "I understand you're interested in weight management."
        transition :weight_management
      end
      
      when match("* muscle * strength *") do
        speak WellnessGuide, "Let's focus on building strength and muscle."
        transition :strength_training
      end
      
      when match("* energy * fatigue *") do
        speak WellnessGuide, "We'll work on improving your energy levels."
        transition :energy_optimization
      end
      
      # Default response
      speak WellnessGuide, "Let's start with a comprehensive assessment."
      transition :full_assessment
    end
  end
  
  beat :full_assessment do
    speak WellnessGuide, "I'll coordinate with our experts to assess different aspects of your health."
    
    parallel do
      direct NutritionExpert, :dietary_assessment, async: true
      direct FitnessTrainer, :fitness_evaluation, async: true
      direct WellnessGuide, :lifestyle_analysis, async: true
    end
    
    speak WellnessGuide, "We're analyzing multiple aspects of your health simultaneously."
    transition :gather_results
  end
  
  beat :gather_results do
    nutrition_data = wait NutritionExpert
    fitness_data = wait FitnessTrainer
    lifestyle_data = wait WellnessGuide
    
    speak WellnessGuide, "Based on our comprehensive analysis:"
    speak NutritionExpert, "Nutritional insights: #{nutrition_data}"
    speak FitnessTrainer, "Fitness assessment: #{fitness_data}"
    speak WellnessGuide, "Lifestyle factors: #{lifestyle_data}"
    
    transition :create_plan
  end
end
```

## Health Monitoring Flow

```sparq
flow LifestyleAnalysis do
  @character WellnessGuide
  @goal "Analyze daily habits and stress levels"
  
  step :gather_metrics do
    when has_user_data?() do
      collect_lifestyle_metrics()
    end
  end
  
  step :analyze_patterns do
    direct NutritionExpert, :get_meal_timing, async: true
    analyze_sleep_patterns()
  end
  
  step :correlate_data do
    meal_data = wait NutritionExpert
    correlate_lifestyle_factors(meal_data)
  end
end
```

## Wellness Tools

```sparq
tool MetricsAnalyzer do
  @description "Analyzes health metrics and identifies patterns"
  @input_type :health_data
  @output_type :analysis_result
  
  def run(data, context) do
    case analyze_health_metrics(data) do
      {:ok, analysis} -> {:ok, format_health_insights(analysis)}
      {:error, reason} -> {:error, "Unable to analyze health data: #{reason}"}
    end
  end
end

tool WorkoutPlanner do
  @description "Generates personalized workout plans"
  @input_type :fitness_preferences
  @output_type :workout_plan
  
  def run(preferences, context) do
    case generate_workout_plan(preferences) do
      {:ok, plan} -> {:ok, format_workout_plan(plan)}
      {:error, reason} -> {:error, "Could not generate workout plan: #{reason}"}
    end
  end
end

tool NutritionCalculator do
  @description "Calculates nutritional needs and meal timing"
  @input_type :user_profile
  @output_type :nutrition_plan
  
  def run(profile, context) do
    case calculate_nutrition_needs(profile) do
      {:ok, plan} -> {:ok, format_nutrition_plan(plan)}
      {:error, reason} -> {:error, "Nutrition calculation failed: #{reason}"}
    end
  end
end
```

## Progress Monitoring Scene

```sparq
scene ProgressCheck do
  @title "Weekly Progress Review"
  @characters [WellnessGuide, NutritionExpert, FitnessTrainer]
  
  beat :start do
    speak WellnessGuide, "Let's review your progress this week."
    
    parallel do
      direct NutritionExpert, :analyze_food_log, async: true
      direct FitnessTrainer, :review_workout_data, async: true
      direct WellnessGuide, :check_wellness_metrics, async: true
    end
    
    speak WellnessGuide, "Analyzing your weekly data..."
    transition :review_progress
  end
  
  beat :review_progress do
    nutrition_progress = wait NutritionExpert
    fitness_progress = wait FitnessTrainer
    wellness_metrics = wait WellnessGuide
    
    speak WellnessGuide, "Here's your weekly progress summary:"
    speak NutritionExpert, "#{nutrition_progress}"
    speak FitnessTrainer, "#{fitness_progress}"
    
    response = ask UserCharacter, "How do you feel about your progress?"
    
    listen response do
      when match("* happy * progress *") do
        speak WellnessGuide, "That's great! Let's keep the momentum going."
        transition :maintain_plan
      end
      
      when match("* struggling *") do
        speak WellnessGuide, "Let's adjust your plan to better suit your needs."
        transition :adjust_plan
      end
      
      # Default response
      speak WellnessGuide, "Thank you for sharing. Let's keep working together."
      transition :continue_plan
    end
  end
end
```

This example demonstrates:
1. Multi-character health assessment coordination
2. Parallel processing of health metrics
3. Sophisticated input handling for health goals
4. Integration of specialized health tools
5. Progress monitoring and plan adjustment