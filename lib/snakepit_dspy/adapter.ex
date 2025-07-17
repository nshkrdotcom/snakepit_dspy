defmodule SnakepitDspy.Adapter do
  @moduledoc """
  DSPy adapter implementation for Snakepit.

  This adapter implements the Snakepit.Adapter behaviour to provide
  DSPy-specific functionality through the Snakepit pooling system.

  ## Supported Commands

  - `ping` - Health check and DSPy availability
  - `create_program` - Create a DSPy program with signature
  - `execute_program` - Execute a DSPy program with inputs
  - `get_program` - Retrieve program information
  - `list_programs` - List all programs in session
  - `delete_program` - Delete a program from session
  - `clear_session` - Clear all programs from session

  ## Configuration

      config :snakepit,
        adapter_module: SnakepitDspy.Adapter
        
      # Optional DSPy-specific configuration
      config :snakepit_dspy,
        default_lm: "openai/gpt-3.5-turbo",
        api_keys: %{
          openai: System.get_env("OPENAI_API_KEY"),
          gemini: System.get_env("GEMINI_API_KEY")
        }

  ## Usage

      # Create a program
      {:ok, result} = Snakepit.execute_in_session("my_session", "create_program", %{
        id: "qa_program",
        signature: %{
          inputs: [%{name: "question", type: "str", description: "Question to answer"}],
          outputs: [%{name: "answer", type: "str", description: "Answer to the question"}]
        },
        instructions: "Answer questions accurately and concisely"
      })
      
      # Execute the program
      {:ok, result} = Snakepit.execute_in_session("my_session", "execute_program", %{
        program_id: "qa_program",
        inputs: %{question: "What is DSPy?"}
      })
  """

  @behaviour Snakepit.Adapter

  @impl true
  def script_path do
    Path.join(:code.priv_dir(:snakepit_dspy), "python/dspy_bridge.py")
  end

  @impl true
  def script_args do
    ["--mode", "pool-worker"]
  end

  @impl true
  def supported_commands do
    [
      "ping",
      "configure_lm",
      "create_program",
      "execute_program",
      "get_program",
      "list_programs",
      "delete_program",
      "clear_session"
    ]
  end

  @impl true
  def validate_command("ping", _args), do: :ok

  def validate_command("create_program", args) do
    with :ok <- validate_required_field(args, "id", "Program ID is required"),
         :ok <- validate_signature(args) do
      :ok
    end
  end

  def validate_command("execute_program", args) do
    with :ok <- validate_required_field(args, "program_id", "Program ID is required"),
         :ok <- validate_required_field(args, "inputs", "Program inputs are required") do
      if is_map(args["inputs"]) or is_map(args[:inputs]) do
        :ok
      else
        {:error, "inputs must be a map"}
      end
    end
  end

  def validate_command("get_program", args) do
    validate_required_field(args, "program_id", "Program ID is required")
  end

  def validate_command("configure_lm", args) do
    with :ok <- validate_required_field(args, "model", "Model name is required"),
         :ok <- validate_required_field(args, "api_key", "API key is required") do
      :ok
    end
  end

  def validate_command("delete_program", args) do
    validate_required_field(args, "program_id", "Program ID is required")
  end

  def validate_command("list_programs", _args), do: :ok
  def validate_command("clear_session", _args), do: :ok

  def validate_command(command, _args) do
    {:error,
     "unsupported command '#{command}'. Supported: #{Enum.join(supported_commands(), ", ")}"}
  end

  @impl true
  def prepare_args(command, args) do
    args
    |> stringify_keys()
    |> add_session_context(command)
    |> add_dspy_config(command)
  end

  @impl true
  def process_response("create_program", response) do
    case response do
      %{"status" => "ok", "program_id" => _} = resp ->
        {:ok, resp}

      %{"status" => "error", "error" => error} ->
        {:error, "program creation failed: #{error}"}

      other ->
        {:ok, other}
    end
  end

  def process_response("execute_program", response) do
    case response do
      %{"status" => "ok", "outputs" => _} = resp ->
        {:ok, resp}

      %{"status" => "error", "error" => error} ->
        {:error, "program execution failed: #{error}"}

      other ->
        {:ok, other}
    end
  end

  def process_response(_command, response) do
    {:ok, response}
  end

  # Private helper functions

  defp validate_required_field(args, field, error_message) do
    if Map.has_key?(args, field) or Map.has_key?(args, String.to_atom(field)) do
      :ok
    else
      {:error, error_message}
    end
  end

  defp validate_signature(args) do
    signature = args["signature"] || args[:signature]

    if signature do
      cond do
        not is_map(signature) ->
          {:error, "signature must be a map"}

        not (Map.has_key?(signature, "inputs") or Map.has_key?(signature, :inputs)) ->
          {:error, "signature must have inputs field"}

        not (Map.has_key?(signature, "outputs") or Map.has_key?(signature, :outputs)) ->
          {:error, "signature must have outputs field"}

        true ->
          :ok
      end
    else
      {:error, "signature is required"}
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list) do
    Enum.map(list, &stringify_keys/1)
  end

  defp stringify_keys(value), do: value

  defp add_session_context(args, _command) do
    # Session context is handled by Snakepit.Pool
    args
  end

  defp add_dspy_config(args, _command) do
    # Add DSPy-specific configuration
    dspy_config = Application.get_env(:snakepit_dspy, :dspy_config, %{})

    if map_size(dspy_config) > 0 do
      Map.put(args, "dspy_config", dspy_config)
    else
      args
    end
  end
end
