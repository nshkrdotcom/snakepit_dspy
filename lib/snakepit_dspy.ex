defmodule SnakepitDspy do
  @moduledoc """
  DSPy adapter for Snakepit.

  Provides both pooled and direct interfaces for DSPy integration:

  ## Pooled Usage (via Snakepit)

  Configure your application to use the DSPy adapter:

      config :snakepit,
        adapter_module: SnakepitDspy.Adapter

  Then use Snakepit's standard interface:

      # Create and execute programs
      {:ok, result} = Snakepit.execute_in_session("my_session", "create_program", %{
        id: "qa_program",
        signature: %{...},
        instructions: "Answer questions accurately"
      })
      
      {:ok, result} = Snakepit.execute_in_session("my_session", "execute_program", %{
        program_id: "qa_program", 
        inputs: %{question: "What is DSPy?"}
      })

  ## Direct Usage (bypass pooling)

  For simpler use cases or when you need direct control:

      # Start a direct DSPy worker
      {:ok, pid} = SnakepitDspy.Direct.start_link()
      
      # Use it directly
      {:ok, result} = SnakepitDspy.Direct.create_program(pid, %{...})
      {:ok, result} = SnakepitDspy.Direct.execute_program(pid, %{...})

  ## Features

  - **High Performance**: Leverages Snakepit's concurrent worker initialization
  - **Session Management**: Automatic program and context management
  - **Error Handling**: Robust error handling and recovery
  - **Flexible Interface**: Both pooled and direct usage patterns
  - **DSPy Integration**: Full DSPy signature and program support
  """

  @doc """
  Convenience function for pooled DSPy execution.

  Requires Snakepit to be configured with SnakepitDspy.Adapter.
  """
  def execute(command, args, opts \\ []) do
    Snakepit.execute(command, args, opts)
  end

  @doc """
  Convenience function for session-based DSPy execution.

  Requires Snakepit to be configured with SnakepitDspy.Adapter.
  """
  def execute_in_session(session_id, command, args, opts \\ []) do
    Snakepit.execute_in_session(session_id, command, args, opts)
  end

  @doc """
  Configure Gemini language model for DSPy operations.

  ## Parameters

  - `api_key` - Gemini API key (defaults to GEMINI_API_KEY env var)
  - `model` - Gemini model name (defaults to gemini-2.5-flash-lite-preview-06-17)
  - `opts` - Additional options (temperature, etc.)

  ## Examples

      SnakepitDspy.configure_gemini()
      SnakepitDspy.configure_gemini("your-api-key")
      SnakepitDspy.configure_gemini("your-api-key", "gemini-1.5-pro")
  """
  def configure_gemini(api_key \\ nil, model \\ "gemini-2.5-flash-lite-preview-06-17", opts \\ []) do
    actual_api_key = api_key || System.get_env("GEMINI_API_KEY")

    unless actual_api_key do
      raise "GEMINI_API_KEY environment variable not set and no API key provided"
    end

    config = %{
      model: model,
      api_key: actual_api_key,
      provider: "google",
      temperature: Keyword.get(opts, :temperature, 0.7)
    }

    execute("configure_lm", config)
  end

  @doc """
  Create a simple Q&A program.

  ## Parameters

  - `program_id` - Unique identifier for the program
  - `instructions` - Instructions for the Q&A behavior

  ## Examples

      {:ok, _} = SnakepitDspy.create_qa_program("my_qa", "Answer questions accurately and concisely")
      {:ok, result} = SnakepitDspy.ask_question("my_qa", "What is Elixir?")
  """
  def create_qa_program(program_id, instructions \\ "Answer questions accurately and concisely") do
    signature = %{
      name: "QuestionAnswer",
      inputs: [%{name: "question", type: "string", description: "A question to answer"}],
      outputs: [%{name: "answer", type: "string", description: "A helpful and accurate answer"}]
    }

    program_def = %{
      id: program_id,
      signature: signature,
      instructions: instructions
    }

    execute("create_program", program_def)
  end

  @doc """
  Ask a question using a Q&A program.

  ## Parameters

  - `program_id` - ID of the Q&A program to use
  - `question` - The question to ask
  - `opts` - Additional options

  ## Examples

      {:ok, result} = SnakepitDspy.ask_question("my_qa", "What are the benefits of Elixir?")
  """
  def ask_question(program_id, question, _opts \\ []) do
    inputs = %{question: question}

    case execute("execute_program", %{program_id: program_id, inputs: inputs}) do
      {:ok, result} ->
        {:ok, Map.get(result, "outputs", %{}) |> Map.get("answer", "No answer provided")}

      error ->
        error
    end
  end

  @doc """
  Create a program with a custom DSPy signature.

  ## Parameters

  - `program_id` - Unique identifier for the program
  - `signature` - DSPy signature definition with inputs/outputs
  - `instructions` - Optional instructions for the program behavior

  ## Examples

      signature = %{
        name: "TechnicalAnalysis",
        inputs: [
          %{name: "code", type: "string", description: "Source code to analyze"},
          %{name: "language", type: "string", description: "Programming language"}
        ],
        outputs: [
          %{name: "analysis", type: "string", description: "Technical analysis of the code"},
          %{name: "suggestions", type: "string", description: "Improvement suggestions"}
        ]
      }
      
      {:ok, _} = SnakepitDspy.create_signature_program("code_analyzer", signature, "Analyze code quality and provide suggestions")
  """
  def create_signature_program(program_id, signature, instructions \\ nil) do
    program_def = %{
      id: program_id,
      signature: signature,
      instructions: instructions
    }

    execute("create_program", program_def)
  end

  @doc """
  Execute a signature-based program.

  ## Parameters

  - `program_id` - ID of the signature program to execute
  - `inputs` - Map of input values matching the signature
  - `opts` - Additional options

  ## Examples

      inputs = %{
        code: "def hello, do: IO.puts('Hello, World!')",
        language: "elixir"
      }
      
      {:ok, result} = SnakepitDspy.execute_signature_program("code_analyzer", inputs)
  """
  def execute_signature_program(program_id, inputs, _opts \\ []) do
    execute("execute_program", %{program_id: program_id, inputs: inputs})
  end

  @doc """
  Get information about the DSPy adapter.
  """
  def adapter_info do
    %{
      name: "SnakepitDspy",
      version: Application.spec(:snakepit_dspy, :vsn) |> to_string(),
      supported_commands: SnakepitDspy.Adapter.supported_commands(),
      dspy_available: check_dspy_availability(),
      pooling_available: Code.ensure_loaded?(Snakepit)
    }
  end

  defp check_dspy_availability do
    # This will be checked by the Python bridge
    :unknown
  end
end
