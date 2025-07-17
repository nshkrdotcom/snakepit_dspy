#!/usr/bin/env elixir

# Comprehensive demo showing real LLM calls using Snakepit pooled interface
# 
# This demo demonstrates:
# 1. Configuring Gemini with the pooled interface
# 2. Creating and using Q&A programs with real LLM calls
# 3. Creating and using signature-based programs with real LLM calls
# 4. Session management and worker pooling
#
# Prerequisites:
# - Set GEMINI_API_KEY environment variable
# - Python 3.8+ with dspy-ai package installed
# - Internet connection for Gemini API calls

# Configure BEFORE Mix.install to ensure proper startup
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, SnakepitDspy.Adapter)
Application.put_env(:snakepit, :pool_config, %{pool_size: 2})

Mix.install([
  {:snakepit_dspy, path: "."}
])

defmodule PooledSignatureDemo do
  @moduledoc """
  Comprehensive demonstration of real LLM calls using Snakepit's pooled interface.
  """

  require Logger

  def run do
    Logger.info("🚀 Starting Pooled Signature Demo with Real Gemini Calls")
    
    # Check prerequisites
    unless System.get_env("GEMINI_API_KEY") do
      Logger.error("❌ GEMINI_API_KEY environment variable not set")
      System.halt(1)
    end

    # Applications are already started by Mix.install with proper config
    # Just ensure they're fully started
    {:ok, _} = Application.ensure_all_started(:snakepit)
    {:ok, _} = Application.ensure_all_started(:snakepit_dspy)

    # Wait for pool to initialize
    Logger.info("⏳ Waiting for pool to initialize...")
    Process.sleep(3000)
    
    # Verify pool is running
    case GenServer.whereis(Snakepit.Pool) do
      nil ->
        Logger.error("❌ Pool not started - check configuration")
        System.halt(1)
      _pid ->
        Logger.info("✅ Pool is running")
    end

    with :ok <- configure_gemini(),
         :ok <- demo_qa_program(),
         :ok <- demo_signature_program() do
      Logger.info("✅ All demos completed successfully!")
    else
      error ->
        Logger.error("❌ Demo failed: #{inspect(error)}")
        System.halt(1)
    end
  end

  defp configure_gemini do
    Logger.info("🔧 Configuring Gemini language model in all workers...")
    
    config = %{
      model: "gemini-2.5-flash-lite-preview-06-17",
      api_key: System.get_env("GEMINI_API_KEY"),
      provider: "google",
      temperature: 0.7
    }
    
    # Configure LM in multiple sessions to reach all workers
    # This ensures each worker has the LM configured locally
    sessions = ["worker_1_session", "worker_2_session", "worker_3_session"]
    
    tasks = Enum.map(sessions, fn session_id ->
      Task.async(fn ->
        case SnakepitDspy.execute_in_session(session_id, "configure_lm", config) do
          {:ok, result} ->
            Logger.info("✅ Gemini configured in #{session_id}: #{inspect(result["message"])}")
            :ok
          {:error, reason} ->
            Logger.warning("⚠️ Failed to configure Gemini in #{session_id}: #{inspect(reason)}")
            {:error, reason}
        end
      end)
    end)
    
    # Wait for all configurations to complete
    results = Task.await_many(tasks, 10_000)
    
    # Check if at least one worker was configured successfully
    success_count = Enum.count(results, &(&1 == :ok))
    
    if success_count > 0 do
      Logger.info("✅ Gemini configured successfully in #{success_count}/#{length(sessions)} workers")
      :ok
    else
      Logger.error("❌ Failed to configure Gemini in any worker")
      {:error, "LM configuration failed in all workers"}
    end
  end

  defp demo_qa_program do
    Logger.info("🤖 Demo 1: Q&A Program with Real LLM Calls")
    
    # Create a Q&A program using session-based execution
    program_id = "demo_qa_#{System.unique_integer([:positive])}"
    instructions = "You are a helpful assistant. Answer questions accurately and concisely."
    
    Logger.info("Creating Q&A program: #{program_id}")
    
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
    
    case SnakepitDspy.execute_in_session("demo_session", "create_program", program_def) do
      {:ok, result} ->
        Logger.info("✅ Q&A program created: #{inspect(result)}")
        
        # Ask multiple questions to demonstrate real LLM calls
        questions = [
          "What is the capital of France?",
          "Explain what Elixir programming language is in one sentence.",
          "What are the benefits of using OTP in distributed systems?"
        ]
        
        Enum.each(questions, fn question ->
          Logger.info("❓ Asking: #{question}")
          
          inputs = %{question: question}
          case SnakepitDspy.execute_in_session("demo_session", "execute_program", %{
            program_id: program_id, 
            inputs: inputs
          }) do
            {:ok, result} ->
              outputs = result["outputs"] || %{}
              answer = outputs["answer"] || "No answer provided"
              Logger.info("💬 Answer: #{answer}")
            {:error, reason} ->
              Logger.error("❌ Failed to get answer: #{inspect(reason)}")
          end
          
          # Small delay between questions
          Process.sleep(500)
        end)
        
        :ok
        
      {:error, reason} ->
        Logger.error("❌ Failed to create Q&A program: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp demo_signature_program do
    Logger.info("📝 Demo 2: Signature Program with Real LLM Calls")
    
    # Create a more complex signature for code analysis
    program_id = "demo_signature_#{System.unique_integer([:positive])}"
    
    signature = %{
      name: "CodeAnalyzer",
      inputs: [
        %{name: "code", type: "string", description: "Source code to analyze"},
        %{name: "language", type: "string", description: "Programming language (e.g., elixir, python, javascript)"}
      ],
      outputs: [
        %{name: "analysis", type: "string", description: "Brief analysis of the code quality and structure"},
        %{name: "suggestions", type: "string", description: "Specific improvement suggestions"}
      ]
    }
    
    instructions = "Analyze the provided code for quality, structure, and best practices. Provide constructive feedback."
    
    Logger.info("Creating signature program: #{program_id}")
    
    case SnakepitDspy.execute_in_session("demo_session", "create_program", %{
      id: program_id,
      signature: signature,
      instructions: instructions
    }) do
      {:ok, result} ->
        Logger.info("✅ Signature program created: #{inspect(result)}")
        
        # Test with different code samples
        code_samples = [
          %{
            code: """
            def factorial(0), do: 1
            def factorial(n) when n > 0, do: n * factorial(n - 1)
            """,
            language: "elixir"
          },
          %{
            code: """
            function fibonacci(n) {
              if (n <= 1) return n;
              return fibonacci(n-1) + fibonacci(n-2);
            }
            """,
            language: "javascript"
          }
        ]
        
        Enum.each(code_samples, fn sample ->
          Logger.info("🔍 Analyzing #{sample.language} code...")
          
          case SnakepitDspy.execute_in_session("demo_session", "execute_program", %{
            program_id: program_id,
            inputs: sample
          }) do
            {:ok, result} ->
              outputs = result["outputs"] || %{}
              analysis = outputs["analysis"] || "No analysis provided"
              suggestions = outputs["suggestions"] || "No suggestions provided"
              
              Logger.info("📊 Analysis: #{analysis}")
              Logger.info("💡 Suggestions: #{suggestions}")
              
            {:error, reason} ->
              Logger.error("❌ Failed to analyze code: #{inspect(reason)}")
          end
          
          # Small delay between analyses
          Process.sleep(500)
        end)
        
        :ok
        
      {:error, reason} ->
        Logger.error("❌ Failed to create signature program: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

# Run the demo
PooledSignatureDemo.run()
