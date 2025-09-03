import { generateText } from "ai";
import { openai } from "@ai-sdk/openai";

// Simple tools for the coding agent
const tools = {
  writeFile: {
    description: "Write content to a file",
    parameters: {
      type: "object",
      properties: {
        filename: { type: "string" },
        content: { type: "string" },
      },
      required: ["filename", "content"],
    },
  },
  readFile: {
    description: "Read content from a file",
    parameters: {
      type: "object",
      properties: {
        filename: { type: "string" },
      },
      required: ["filename"],
    },
  },
  runCode: {
    description: "Execute code and return the result",
    parameters: {
      type: "object",
      properties: {
        code: { type: "string" },
        language: { type: "string" },
      },
      required: ["code", "language"],
    },
  },
};

// Mock tool implementations (replace with real ones)
async function executeTool(name: string, args: any) {
  switch (name) {
    case "writeFile":
      console.log(`📝 Writing to ${args.filename}`);
      // In real implementation: fs.writeFile(args.filename, args.content)
      return `Successfully wrote to ${args.filename}`;

    case "readFile":
      console.log(`📖 Reading ${args.filename}`);
      // In real implementation: fs.readFile(args.filename)
      return `// Content of ${args.filename}\nconsole.log("Hello World");`;

    case "runCode":
      console.log(`🏃 Running ${args.language} code`);
      // In real implementation: execute code in sandbox
      return `Output: Hello World\nExit code: 0`;

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// The simple event loop
export async function codingAgentLoop(initialTask: string, maxIterations = 10) {
  let messages = [
    {
      role: "user" as const,
      content: `You are a coding agent. Complete this task: ${initialTask}

You can use these tools:
- writeFile: to create/modify files
- readFile: to examine existing files  
- runCode: to test code

Work step by step. When you're completely done, end your response with "TASK_COMPLETE".`,
    },
  ];

  for (let iteration = 0; iteration < maxIterations; iteration++) {
    console.log(`\n--- Iteration ${iteration + 1} ---`);

    // Generate response with tool calling capability
    const result = await generateText({
      model: openai("gpt-4"),
      messages,
      tools,
      temperature: 0.1,
    });

    console.log("🤖 Agent response:", result.text);

    // Add the assistant's response to conversation
    messages.push({
      role: "assistant" as const,
      content: result.text,
    });

    // Check if task is complete
    if (result.text.includes("TASK_COMPLETE")) {
      console.log("✅ Task completed!");
      break;
    }

    // Execute any tool calls
    if (result.toolCalls && result.toolCalls.length > 0) {
      let toolResults = [];

      for (const toolCall of result.toolCalls) {
        console.log(`🔧 Calling tool: ${toolCall.toolName}`);
        console.log("📥 Args:", toolCall.args);

        try {
          const toolResult = await executeTool(
            toolCall.toolName,
            toolCall.args
          );
          console.log("📤 Result:", toolResult);

          toolResults.push({
            toolCallId: toolCall.toolCallId,
            result: toolResult,
          });
        } catch (error) {
          toolResults.push({
            toolCallId: toolCall.toolCallId,
            result: `Error: ${error.message}`,
          });
        }
      }

      // Add tool results back to conversation
      messages.push({
        role: "tool" as const,
        content: toolResults
          .map((r) => `Tool ${r.toolCallId}: ${r.result}`)
          .join("\n"),
      });
    }

    // If no tool calls and not complete, we might be stuck
    if (!result.toolCalls?.length && !result.text.includes("TASK_COMPLETE")) {
      console.log(
        "🤔 No tools called and not complete. Adding prompt to continue..."
      );
      messages.push({
        role: "user" as const,
        content: "Continue with the next step or call TASK_COMPLETE if done.",
      });
    }
  }

  return messages;
}

// Even simpler version - just the core loop
export async function simpleCodingLoop(task: string) {
  let conversation = `Task: ${task}\n\n`;

  for (let i = 0; i < 5; i++) {
    const result = await generateText({
      model: openai("gpt-4"),
      prompt: `${conversation}

Continue working on this coding task. Use tools as needed:
${
  i === 0
    ? "Start by analyzing what needs to be done."
    : "Continue from where you left off."
}`,
      tools,
    });

    conversation += `Step ${i + 1}:\n${result.text}\n\n`;

    // Execute tools if any were called
    if (result.toolCalls?.length) {
      for (const call of result.toolCalls) {
        const toolResult = await executeTool(call.toolName, call.args);
        conversation += `Tool Result: ${toolResult}\n`;
      }
      conversation += "\n";
    }

    // Check if done
    if (result.text.includes("TASK_COMPLETE")) {
      break;
    }
  }

  return conversation;
}

// Usage
export async function runExample() {
  const task =
    "Create a simple Node.js script that reads a JSON file and counts the number of objects in it";

  console.log("🚀 Starting coding agent...");
  await codingAgentLoop(task);
}
