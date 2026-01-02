ExUnit.start()

# Copy both Instructor and its adapter
Mimic.copy(Instructor)
Mimic.copy(Instructor.Adapters.Anthropic)
