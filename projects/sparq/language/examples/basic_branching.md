# Basic Branching Example

This example extends the minimal approach with a single character who presents two branching choices in one scene.

```sparq
character BasicHelper do
  @name "Basic Helper"
  @goal "Offer simple branching choices to the user"
  @backstory "A slightly more advanced character to demonstrate branching"
end

scene BranchingDemo do
  @title "Basic Branching Demo"
  @characters [BasicHelper]

  beat :start do
    speak BasicHelper, "Welcome! Would you like to learn something new or just say hello?"
    
    choose do
      option "Teach me something new", :teaching_path
      option "Just say hello", :hello_path
    end
  end

  beat :teaching_path do
    speak BasicHelper, "Alright! Let's learn about the Sparq DSL basics."
    narrate "Here, you could insert educational content or transitions."
    transition :end
  end

  beat :hello_path do
    speak BasicHelper, "Hello again! Keep it simple, right?"
    transition :end
  end

  beat :end do
    speak BasicHelper, "Thanks for branching with me!"
  end
end
```

## Explanation
- **Character**: `BasicHelper`, offering more than a single greeting.
- **Scene**: `BranchingDemo` has multiple beats with a branching choice using `choose`.
- **Choice**: Two options for the user to pick, each leading to a different beat.
- **End**: The final beat `:end` wraps up the conversation.