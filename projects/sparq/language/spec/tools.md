# Sparq Tool Specification

A tool in Sparq represents a specific capability that characters can use. Each tool is defined as a module that provides a single `run/2` function, which performs a specific task. Tools are the basic skills that characters can use within flows and scenes.

## Basic Tool Structure

```sparq
tool SearchDocs do
  @description "Search through documentation for relevant information"
  @input_type :string  
  @output_type :result_list
  
  # The run/2 function is automatically defined based on these specifications
  # First argument is input, second is context
end
```

## Required Attributes

- `@description`: Clear explanation of the tool's purpose
- `@input_type`: Expected input type
- `@output_type`: Type of result returned

## Optional Attributes

- `@timeout`: Maximum execution time
- `@retry`: Retry configuration for failures
- `@rate_limit`: Usage rate limiting
- `@permissions`: Required access levels

## Custom Implementation

Here's how to provide a custom implementation:

```sparq
tool SearchDocs do
  @description "Search through documentation for relevant information"
  @input_type :string
  @output_type :result_list
  @timeout :timer.seconds(30)
  @retry %{max_attempts: 3, delay: :timer.seconds(1)}
  
  def run(query, context) do
    case do_search(query) do
      {:ok, results} -> {:ok, results}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Using Tools in Flows

Tools become available to characters that have access to them:

```sparq
flow ResearchTopic do
  @character Researcher
  @goal "Research a specific topic"
  
  step :gather_info do
    # Use the SearchDocs tool
    case SearchDocs.run(query, context) do
      {:ok, results} -> process_results(results)
      {:error, _} -> fallback_search()
    end
  end
end
```

## Tool Categories

1. Information Tools
   - Document search
   - Knowledge base queries
   - Data analysis

2. Communication Tools
   - Message formatting
   - Translation
   - Notification sending

3. System Tools
   - Diagnostics
   - Resource management
   - Monitoring

## Best Practices

1. Tool Design
   - Keep tools focused on a single task
   - Use clear, descriptive names
   - Document inputs and outputs
   - Handle errors gracefully

2. Error Handling
   - Always return {:ok, result} | {:error, reason}
   - Set appropriate timeouts
   - Configure retries for flaky operations
   - Provide meaningful error messages

3. Performance
   - Implement rate limiting when needed
   - Cache results when appropriate
   - Monitor resource usage
   - Set reasonable timeouts

4. Security
   - Validate inputs
   - Check permissions
   - Sanitize outputs
   - Log important operations