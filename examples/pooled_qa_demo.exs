#!/usr/bin/env elixir

# Pooled Q&A demo - 3 questions using Snakepit pooler
# 
# This demo shows Q&A using the pooled interface for multiple questions

# Configure BEFORE Mix.install to ensure proper startup
Application.put_env(:snakepit, :pooling_enabled, true)
Application.put_env(:snakepit, :adapter_module, SnakepitDspy.Adapter)
Application.put_env(:snakepit, :pool_config, %{pool_size: 2})

Mix.install([
  {:snakepit_dspy, path: "."}
])

defmodule PooledQADemo do
  @moduledoc """
  Demonstrates 3 Q&A calls using Snakepit's pooled interface.
  Shows load balancing across workers.
  """

  require Logger

  def run do
    Logger.info("🚀 Pooled Q&A Demo - 3 Questions with Worker Pool")
    
    # Check prerequisites
    unless System.get_env("GEMINI_API_KEY") do
      Logger.error("❌ GEMINI_API_KEY environment variable not set")
      System.halt(1)
    end

    # Applications are already started by Mix.install with proper config
    {:ok, _} = Application.ensure_all_started(:snakepit)
    {:ok, _} = Application.ensure_all_started(:snakepit_dspy)

    # Wait for pool to initialize
    Logger.info("⏳ Waiting for pool to initialize...")
    
    # Verify pool is running
    case GenServer.whereis(Snakepit.Pool) do
      nil ->
        Logger.error("❌ Pool not started - check configuration")
        System.halt(1)
      _pid ->
        Logger.info("✅ Pool is running")
    end

    with :ok <- configure_gemini(),
         :ok <- demo_qa_questions() do
      Logger.info("✅ All Q&A demos completed successfully!")
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
      provider: "google"
    }
    
    # Configure LM in multiple sessions to reach all workers
    sessions = ["worker_1_session", "worker_2_session"]
    
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

  defp demo_qa_questions do
    Logger.info("🤖 Demo: 3 Q&A Questions with Pooled Workers")
    
    # Create a Q&A program
    program_id = "pooled_qa_#{System.unique_integer([:positive])}"
    
    signature = %{
      name: "PooledQA",
      inputs: [%{name: "question", type: "string", description: "A question to answer"}],
      outputs: [%{name: "answer", type: "string", description: "A helpful and accurate answer"}]
    }
    
    program_def = %{
      id: program_id,
      signature: signature,
      instructions: "You are a helpful assistant. Answer questions accurately and concisely."
    }
    
    case SnakepitDspy.execute_in_session("qa_session", "create_program", program_def) do
      {:ok, _result} ->
        Logger.info("✅ Q&A program created: #{program_id}")
        
        # Ask 3 different questions - they'll be load balanced across workers
        questions = [
          "What is functional programming?",
          "How does the Actor model work in Elixir?", 
          "What are the main benefits of immutable data structures?"
        ]
        
        Enum.with_index(questions, 1) |> Enum.each(fn {question, index} ->
          Logger.info("❓ Question #{index}: #{question}")
          
          inputs = %{question: question}
          case SnakepitDspy.execute_in_session("qa_session", "execute_program", %{
            program_id: program_id, 
            inputs: inputs
          }) do
            {:ok, result} ->
              outputs = result["outputs"] || %{}
              answer = outputs["answer"] || "No answer provided"
              Logger.info("💬 Answer #{index}: #{answer}")
            {:error, reason} ->
              Logger.error("❌ Failed to get answer #{index}: #{inspect(reason)}")
          end
          
          # Load balancing happens automatically
        end)
        
        :ok
        
      {:error, reason} ->
        Logger.error("❌ Failed to create Q&A program: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

# Run the demo
PooledQADemo.run()
