#!/usr/bin/env elixir

# Simple direct Q&A demo - just ONE direct LM call bypass
# 
# This demo shows the minimal setup for a single Q&A call
# using DSPy directly without any Snakepit pooling or signatures

# Disable pooling for direct interface
Application.put_env(:snakepit, :pooling_enabled, false)

Mix.install([
  {:snakepit_dspy, path: "."}
])

defmodule SimpleQABypassDemo do
  @moduledoc """
  Demonstrates a single direct Q&A call bypassing Snakepit completely.
  Just raw DSPy LM interaction for one question/answer.
  """

  require Logger

  def run do
    Logger.info("🚀 Simple Q&A Bypass Demo - Direct DSPy Call")
    
    # Check prerequisites
    unless System.get_env("GEMINI_API_KEY") do
      Logger.error("❌ GEMINI_API_KEY environment variable not set")
      System.halt(1)
    end

    # Start a single direct worker (no pool)
    {:ok, worker} = SnakepitDspy.Direct.start_link()
    Logger.info("✅ Direct worker started")

    try do
      # Configure Gemini
      Logger.info("🔧 Configuring Gemini...")
      config = %{
        model: "gemini-2.5-flash-lite-preview-06-17",
        api_key: System.get_env("GEMINI_API_KEY"),
        provider: "google"
      }
      
      {:ok, _result} = SnakepitDspy.Direct.configure_lm(worker, config)
      Logger.info("✅ Gemini configured")

      # Create a simple Q&A signature
      Logger.info("📝 Creating simple Q&A signature...")
      signature = %{
        name: "SimpleQA", 
        inputs: [
          %{name: "question", type: "string", description: "A question to answer"}
        ],
        outputs: [
          %{name: "answer", type: "string", description: "A concise, helpful answer"}
        ]
      }

      program_def = %{
        id: "simple_qa",
        signature: signature,
        instructions: "Answer the question directly and concisely."
      }

      {:ok, _result} = SnakepitDspy.Direct.create_program(worker, program_def)
      Logger.info("✅ Q&A program created")

      # Ask one simple question
      question = "What programming language was created by José Valim?"
      Logger.info("❓ Asking: #{question}")
      
      inputs = %{question: question}
      execution_args = %{
        program_id: "simple_qa",
        inputs: inputs
      }

      {:ok, result} = SnakepitDspy.Direct.execute_program(worker, execution_args)
      
      # Display result
      outputs = result["outputs"] || %{}
      answer = outputs["answer"] || "No answer provided"
      
      Logger.info("💬 Answer: #{answer}")
      Logger.info("✅ Demo completed successfully!")

    rescue
      error ->
        Logger.error("❌ Demo failed: #{inspect(error)}")
        System.halt(1)
    after
      # Clean shutdown
      SnakepitDspy.Direct.stop(worker)
      Logger.info("🔄 Worker stopped")
    end
  end
end

# Run the demo
SimpleQABypassDemo.run()
