#!/usr/bin/env elixir

# Simple non-pooled signature demo - just ONE signature call
# 
# This demo shows the minimal setup for a single signature-based LLM call
# using Snakepit's direct interface (no pooling, no sessions)

# Disable pooling for direct interface
Application.put_env(:snakepit, :pooling_enabled, false)

Mix.install([
  {:snakepit_dspy, path: "."}
])

defmodule SimpleSignatureDemo do
  @moduledoc """
  Demonstrates a single signature call using the direct interface.
  """

  require Logger

  def run do
    Logger.info("🚀 Simple Signature Demo - Single Call")
    
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

      # Create a signature for code review
      Logger.info("📝 Creating code review signature...")
      signature = %{
        name: "CodeReviewer", 
        inputs: [
          %{name: "code", type: "string", description: "Code to review"},
          %{name: "focus", type: "string", description: "What aspect to focus on (e.g., security, performance, style)"}
        ],
        outputs: [
          %{name: "rating", type: "string", description: "Overall rating from 1-10 with brief justification"},
          %{name: "feedback", type: "string", description: "Specific actionable feedback"}
        ]
      }

      program_def = %{
        id: "code_reviewer",
        signature: signature,
        instructions: "You are an expert code reviewer. Provide honest, constructive feedback."
      }

      {:ok, _result} = SnakepitDspy.Direct.create_program(worker, program_def)
      Logger.info("✅ Signature program created")

      # Execute the signature with a simple code example
      Logger.info("🔍 Analyzing code...")
      code_to_review = """
      def process_users(users) do
        users
        |> Enum.map(fn user -> 
             String.downcase(user.email)
           end)
        |> Enum.uniq()
      end
      """

      inputs = %{
        code: code_to_review,
        focus: "performance and best practices"
      }

      execution_args = %{
        program_id: "code_reviewer",
        inputs: inputs
      }

      {:ok, result} = SnakepitDspy.Direct.execute_program(worker, execution_args)
      
      # Display results
      outputs = result["outputs"] || %{}
      rating = outputs["rating"] || "No rating provided"
      feedback = outputs["feedback"] || "No feedback provided"
      
      Logger.info("⭐ Rating: #{rating}")
      Logger.info("💡 Feedback: #{feedback}")
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
SimpleSignatureDemo.run()
