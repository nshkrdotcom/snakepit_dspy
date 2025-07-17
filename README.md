# SnakepitDspy

DSPy adapter for [Snakepit](https://github.com/nshkrdotcom/snakepit) - provides high-performance DSPy integration with both pooled and direct interfaces.

## Overview

SnakepitDspy bridges the gap between Elixir and Python's DSPy library, offering:

- **Pooled Interface**: High-performance DSPy operations via Snakepit's concurrent worker pool
- **Direct Interface**: Simple DSPy access without pooling overhead
- **Session Management**: Automatic program and context management
- **Error Handling**: Robust error handling and recovery
- **Type Safety**: Validated command and argument handling

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Your App      │    │  SnakepitDspy    │    │   Snakepit      │
│                 │    │                  │    │                 │
│ - Business      │───▶│ - DSPy Adapter   │───▶│ - Pool Manager  │
│   Logic         │    │ - Direct Interface│    │ - Workers      │
│ - DSPy Calls    │    │ - Validation     │    │ - Sessions     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │  dspy_bridge.py  │    │ Python Workers  │
                       │                  │    │                 │
                       │ - DSPy Programs  │    │ - Concurrent    │
                       │ - Signatures     │    │ - Isolated      │
                       │ - Execution      │    │ - Managed       │
                       └──────────────────┘    └─────────────────┘
```

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:snakepit, "~> 0.0.1"},
    {:snakepit_dspy, "~> 0.0.1"}
  ]
end
```

## Configuration

### For Pooled Usage

Configure Snakepit to use the DSPy adapter:

```elixir
# config/config.exs
config :snakepit,
  pooling_enabled: true,
  adapter_module: SnakepitDspy.Adapter,
  pool_config: %{
    pool_size: 4
  }

# Optional DSPy-specific configuration
config :snakepit_dspy,
  dspy_config: %{
    default_lm: "openai/gpt-3.5-turbo"
  }
```

### Environment Variables

```bash
# For Gemini API (optional)
export GEMINI_API_KEY="your-gemini-api-key"

# For OpenAI (if using OpenAI models)
export OPENAI_API_KEY="your-openai-api-key"
```

## Usage

### Pooled Interface (Recommended)

Use Snakepit's high-performance pooling:

```elixir
# Start your application (Snakepit starts automatically)
{:ok, _} = Application.ensure_all_started(:your_app)

# Create a DSPy program
{:ok, result} = SnakepitDspy.execute_in_session("my_session", "create_program", %{
  id: "qa_program",
  signature: %{
    inputs: [
      %{name: "question", type: "str", description: "Question to answer"}
    ],
    outputs: [
      %{name: "answer", type: "str", description: "Answer to the question"}  
    ]
  },
  instructions: "Answer questions accurately and concisely"
})

# Execute the program
{:ok, result} = SnakepitDspy.execute_in_session("my_session", "execute_program", %{
  program_id: "qa_program",
  inputs: %{question: "What is DSPy?"}
})

answer = get_in(result, ["outputs", "answer"])
```

### Direct Interface

For simpler use cases or when you don't need pooling:

```elixir
# Start a direct worker
{:ok, worker} = SnakepitDspy.Direct.start_link()

# Create a program
{:ok, _} = SnakepitDspy.Direct.create_program(worker, %{
  id: "sentiment_analyzer",
  signature: %{
    inputs: [%{name: "text", type: "str"}],
    outputs: [%{name: "sentiment", type: "str"}]
  },
  instructions: "Analyze sentiment as positive, negative, or neutral"
})

# Execute the program
{:ok, result} = SnakepitDspy.Direct.execute_program(worker, %{
  program_id: "sentiment_analyzer", 
  inputs: %{text: "I love this!"}
})

# Clean up
SnakepitDspy.Direct.stop(worker)
```

## Supported Commands

### Program Management
- `create_program` - Create a new DSPy program
- `execute_program` - Execute a program with inputs
- `get_program` - Get program information
- `list_programs` - List all programs in session
- `delete_program` - Delete a program
- `clear_session` - Clear all programs from session

### Health & Diagnostics  
- `ping` - Health check and system information

## Examples

See the [demo application](examples/demo_app/) for comprehensive examples including:

- Q&A programs with complex signatures
- Sentiment analysis
- Performance comparisons
- Error handling patterns
- Session management

### Running the Demo

```bash
cd examples/demo_app
elixir run_demo.exs

# For performance comparison
elixir run_demo.exs --performance
```

## Performance

SnakepitDspy leverages Snakepit's concurrent worker initialization for significant performance improvements:

- **1000x+ faster startup** compared to sequential initialization
- **Concurrent execution** across multiple Python workers
- **Session affinity** for stateful program execution
- **Automatic scaling** based on system resources

## Error Handling

All operations return `{:ok, result}` or `{:error, reason}` tuples:

```elixir
case SnakepitDspy.execute_in_session(session, "execute_program", args) do
  {:ok, result} ->
    # Handle success
    process_result(result)
    
  {:error, {:validation_failed, reason}} ->
    # Handle validation errors
    IO.puts("Validation failed: #{reason}")
    
  {:error, reason} ->
    # Handle other errors
    IO.puts("Execution failed: #{inspect(reason)}")
end
```

## Requirements

- **Elixir** 1.18+
- **Python** 3.8+
- **DSPy** library (`pip install dspy-ai`)
- **API Keys** for your chosen language model (Gemini, OpenAI, etc.)

## Development

```bash
# Get dependencies
mix deps.get

# Run tests
mix test

# Run the demo
cd examples/demo_app && elixir run_demo.exs
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT

## Related Projects

- [Snakepit](https://github.com/nshkrdotcom/snakepit) - High-performance pooler and session manager
- [DSPy](https://github.com/stanfordnlp/dspy) - Programming framework for language models
- [DSPex](https://github.com/nshkrdotcom/dspex) - Advanced DSPy integration for Elixir