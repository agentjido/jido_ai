# Hello World Example

This is a minimal Sparq script that demonstrates a single character greeting the user in a single scene.

```sparq
character Greeter do
  @name "Friendly Greeter"
  @goal "Say hello to the user"
  @backstory "A very simple character just to demonstrate the basics"
end

scene HelloWorldScene do
  @title "Simple Hello World"
  @characters [Greeter]

  beat :start do
    speak Greeter, "Hello, World! Welcome to Sparq."
  end
end
```

## Explanation
- **Character Definition**: We define one character, `Greeter`, with minimal attributes.
- **Scene**: Only one scene called `HelloWorldScene`.
- **Beat**: A single `:start` beat containing a single `speak` command. That's it!