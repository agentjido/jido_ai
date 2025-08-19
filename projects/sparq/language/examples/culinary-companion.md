# Culinary Companion Example

This example demonstrates a personal chef assistant using Sparq's concurrent recipe processing and adaptive meal planning features.

## Character Definitions

```sparq
character CulinaryCompanion do
  @name "Culinary Companion"
  @goal "Create personalized, delicious meal plans while accommodating dietary needs"
  @backstory """
  An experienced chef with expertise in various cuisines and dietary requirements,
  focused on making healthy cooking accessible and enjoyable.
  """
end

character NutritionistChef do
  @name "Nutritionist Chef"
  @goal "Ensure meals meet nutritional requirements while maintaining flavor"
  @backstory "Specialized in therapeutic cooking and nutritional optimization"
end

character PantryManager do
  @name "Pantry Manager"
  @goal "Optimize ingredient usage and shopping lists"
  @backstory "Expert in inventory management and ingredient substitution"
end
```

## Meal Planning Scene

```sparq
scene MealPlanning do
  @title "Weekly Meal Plan Creation"
  @characters [CulinaryCompanion, NutritionistChef, PantryManager]
  
  beat :start do
    speak CulinaryCompanion, "Let's create your personalized meal plan for the week."
    
    response = ask UserCharacter, "Do you have any dietary preferences or restrictions?"
    
    listen response do
      when match("* vegetarian *") do
        speak CulinaryCompanion, "I'll create a vegetarian meal plan with complete protein sources."
        transition :plan_vegetarian
      end
      
      when match("* gluten * free *") do
        speak CulinaryCompanion, "I'll ensure all recipes are gluten-free."
        transition :plan_gluten_free
      end
      
      when match("* low * carb *") do
        speak CulinaryCompanion, "I'll focus on low-carb options rich in nutrients."
        transition :plan_low_carb
      end
      
      # Default response
      speak CulinaryCompanion, "I'll create a balanced meal plan for you."
      transition :plan_balanced
    end
  end
  
  beat :plan_balanced do
    speak CulinaryCompanion, "I'll coordinate with our team to create your perfect meal plan."
    
    parallel do
      direct NutritionistChef, :analyze_nutrition_needs, async: true
      direct PantryManager, :check_ingredients, async: true
      direct CulinaryCompanion, :draft_meal_plan, async: true
    end
    
    speak CulinaryCompanion, "Creating your personalized plan..."
    transition :finalize_plan
  end
  
  beat :finalize_plan do
    nutrition_requirements = wait NutritionistChef
    available_ingredients = wait PantryManager
    draft_plan = wait CulinaryCompanion
    
    speak CulinaryCompanion, "Here's what I've planned for your week:"
    speak NutritionistChef, "Nutritional balance: #{nutrition_requirements}"
    speak PantryManager, "Shopping list: #{available_ingredients}"
    
    response = ask UserCharacter, "How does this meal plan look to you?"
    
    listen response do
      when match("* looks * good *") do
        speak CulinaryCompanion, "Great! Let's get started with the shopping list."
        transition :generate_shopping_list
      end
      
      when match("* adjust *") do
        speak CulinaryCompanion, "I'll make some adjustments to better suit your preferences."
        transition :adjust_plan
      end
      
      # Default response
      speak CulinaryCompanion, "Let me know if you'd like any changes."
      transition :review_plan
    end
  end
end
```

## Recipe Adaptation Flow

```sparq
flow RecipeAdaptation do
  @character CulinaryCompanion
  @goal "Adapt recipes based on preferences and available ingredients"
  
  step :analyze_recipe do
    when has_recipe_details?() do
      identify_key_components()
    end
  end
  
  step :find_substitutions do
    direct PantryManager, :check_alternatives, async: true
    analyze_cooking_methods()
  end
  
  step :validate_changes do
    alternatives = wait PantryManager
    verify_recipe_integrity(alternatives)
  end
end
```

## Culinary Tools

```sparq
tool RecipeAdapter do
  @description "Adapts recipes based on dietary restrictions and preferences"
  @input_type :recipe_requirements
  @output_type :adapted_recipe
  
  def run(requirements, context) do
    case adapt_recipe(requirements) do
      {:ok, recipe} -> {:ok, format_recipe(recipe)}
      {:error, reason} -> {:error, "Recipe adaptation failed: #{reason}"}
    end
  end
end

tool IngredientSubstituter do
  @description "Finds suitable ingredient substitutions"
  @input_type :ingredient_request
  @output_type :substitution_options
  
  def run(request, context) do
    case find_substitutions(request) do
      {:ok, options} -> {:ok, format_substitutions(options)}
      {:error, reason} -> {:error, "Substitution search failed: #{reason}"}
    end
  end
end

tool ShoppingListOptimizer do
  @description "Optimizes shopping lists for efficiency"
  @input_type :meal_plan
  @output_type :shopping_list
  
  def run(plan, context) do
    case optimize_shopping_list(plan) do
      {:ok, list} -> {:ok, format_shopping_list(list)}
      {:error, reason} -> {:error, "Shopping list generation failed: #{reason}"}
    end
  end
end
```

## Cooking Guidance Scene

```sparq
scene CookingSession do
  @title "Interactive Cooking Guide"
  @characters [CulinaryCompanion, NutritionistChef]
  
  beat :start do
    speak CulinaryCompanion, "I'll guide you through preparing this meal."
    
    parallel do
      direct CulinaryCompanion, :prepare_instructions, async: true
      direct NutritionistChef, :note_nutrition_tips, async: true
    end
    
    speak CulinaryCompanion, "Getting everything ready..."
    transition :begin_cooking
  end
  
  beat :begin_cooking do
    instructions = wait CulinaryCompanion
    nutrition_tips = wait NutritionistChef
    
    speak CulinaryCompanion, "Let's start cooking! #{instructions}"
    speak NutritionistChef, "Nutrition tip: #{nutrition_tips}"
    
    response = ask UserCharacter, "Are you ready to begin?"
    
    listen response do
      when match("* ready *") do
        speak CulinaryCompanion, "Excellent! Let's start with the prep work."
        transition :cooking_steps
      end
      
      when match("* question *") do
        speak CulinaryCompanion, "I'll be happy to clarify anything."
        transition :answer_questions
      end
      
      # Default response
      speak CulinaryCompanion, "Take your time to get organized."
      transition :preparation
    end
  end
end
```

This example demonstrates:
1. Multi-character meal planning coordination
2. Parallel processing of nutritional requirements and ingredients
3. Sophisticated input handling for dietary preferences
4. Integration of specialized culinary tools
5. Interactive cooking guidance with real-time support 