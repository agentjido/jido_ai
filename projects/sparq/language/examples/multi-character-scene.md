# Multi-Character Scene Example

This example introduces two characters collaborating in a single scene, demonstrating both branching and a parallel execution block.

```sparq
character GuideOne do
  @name "Guide One"
  @goal "Provide the user with initial guidance"
  @backstory "Works closely with Guide Two to handle tasks"
end

character GuideTwo do
  @name "Guide Two"
  @goal "Assist with parallel tasks and additional instructions"
  @backstory "Often runs tasks concurrently with Guide One"
end

scene MultiCharacterDemo do
  @title "Two Guides, One Scene"
  @characters [GuideOne, GuideTwo]

  beat :start do
    speak GuideOne, "Hello! I'm Guide One. My colleague, Guide Two, is here as well."
    speak GuideTwo, "Hello! I'm Guide Two. Let's work together to assist you."

    choose do
      option "Tell me more about your collaboration", :explain_parallel
      option "I just want to greet you both", :simple_greeting
    end
  end

  beat :explain_parallel do
    speak GuideOne, "We can perform tasks in parallel to help you faster."
    speak GuideTwo, "Let me show you an example of parallel tasks."

    parallel do
      direct GuideOne, :some_flow, async: true
      direct GuideTwo, :another_flow, async: true
    end

    speak GuideOne, "Both tasks are now running at the same time!"
    transition :end
  end

  beat :simple_greeting do
    speak GuideOne, "It's nice to meet you. Let us know if you need anything."
    speak GuideTwo, "Yes, we're here to help whenever you're ready."
    transition :end
  end

  beat :end do
    speak GuideOne, "Thank you for visiting our multi-character example!"
  end
end
```

## Explanation
- **Characters**: Two characters (`GuideOne`, `GuideTwo`) with distinct goals.
- **Scene**: A single scene, `MultiCharacterDemo`, containing multiple beats.
- **Choice**: The user can ask about collaboration or just greet.
- **Parallel**: Demonstrates concurrent tasks in `:explain_parallel` beat using `parallel`.