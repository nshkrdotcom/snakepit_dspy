defmodule SnakepitDspy.Direct do
  @moduledoc """
  Direct DSPy interface that bypasses Snakepit pooling.

  This module provides a simple, direct interface to DSPy without requiring
  Snakepit's pooling system. Useful for:

  - Simple applications that don't need pooling
  - Testing and development
  - Integration with existing systems
  - One-off DSPy operations

  ## Usage

      # Start a direct DSPy worker
      {:ok, worker} = SnakepitDspy.Direct.start_link()
      
      # Create a program
      {:ok, result} = SnakepitDspy.Direct.create_program(worker, %{
        id: "qa_program",
        signature: %{
          inputs: [%{name: "question", type: "str"}],
          outputs: [%{name: "answer", type: "str"}]
        },
        instructions: "Answer questions accurately"
      })
      
      # Execute the program
      {:ok, result} = SnakepitDspy.Direct.execute_program(worker, %{
        program_id: "qa_program",
        inputs: %{question: "What is DSPy?"}
      })
      
      # Clean shutdown
      SnakepitDspy.Direct.stop(worker)

  ## Session Management

  Each direct worker maintains its own session state. Programs created
  in one worker are not available in another worker.

  ## Error Handling

  All functions return `{:ok, result}` or `{:error, reason}` tuples.
  """

  use GenServer
  require Logger

  alias Snakepit.Bridge.Protocol

  @default_timeout 30_000

  defstruct [
    :port,
    :python_pid,
    :pending_requests,
    :request_counter
  ]

  # Client API

  @doc """
  Starts a direct DSPy worker.

  ## Options

  - `:timeout` - Timeout for initialization (default: 30s)
  - `:name` - Name to register the process
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Stops a direct DSPy worker.
  """
  def stop(worker, timeout \\ 5000) do
    GenServer.stop(worker, :normal, timeout)
  end

  @doc """
  Sends a ping to check if the worker is responsive.
  """
  def ping(worker, timeout \\ @default_timeout) do
    execute_command(worker, "ping", %{}, timeout)
  end

  @doc """
  Creates a DSPy program.

  ## Parameters

  - `worker` - The worker process
  - `program_def` - Map containing:
    - `id` - Unique program identifier
    - `signature` - Input/output signature definition
    - `instructions` - Instructions for the program
  - `timeout` - Operation timeout (optional)
  """
  def create_program(worker, program_def, timeout \\ @default_timeout) do
    execute_command(worker, "create_program", program_def, timeout)
  end

  @doc """
  Executes a DSPy program.

  ## Parameters

  - `worker` - The worker process
  - `execution_args` - Map containing:
    - `program_id` - ID of the program to execute
    - `inputs` - Input values for the program
  - `timeout` - Operation timeout (optional)
  """
  def execute_program(worker, execution_args, timeout \\ @default_timeout) do
    execute_command(worker, "execute_program", execution_args, timeout)
  end

  @doc """
  Gets information about a program.
  """
  def get_program(worker, program_id, timeout \\ @default_timeout) do
    execute_command(worker, "get_program", %{program_id: program_id}, timeout)
  end

  @doc """
  Lists all programs in the worker's session.
  """
  def list_programs(worker, timeout \\ @default_timeout) do
    execute_command(worker, "list_programs", %{}, timeout)
  end

  @doc """
  Deletes a program from the worker's session.
  """
  def delete_program(worker, program_id, timeout \\ @default_timeout) do
    execute_command(worker, "delete_program", %{program_id: program_id}, timeout)
  end

  @doc """
  Clears all programs from the worker's session.
  """
  def clear_session(worker, timeout \\ @default_timeout) do
    execute_command(worker, "clear_session", %{}, timeout)
  end

  @doc """
  Configures the language model for the worker.

  ## Parameters

  - `worker` - The worker process
  - `config` - Map containing:
    - `model` - Model name (e.g., "gemini-2.5-flash-lite-preview-06-17")
    - `api_key` - API key for the model provider
    - `provider` - Provider name (e.g., "google")
  - `timeout` - Operation timeout (optional)
  """
  def configure_lm(worker, config, timeout \\ @default_timeout) do
    execute_command(worker, "configure_lm", config, timeout)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case start_python_bridge() do
      {:ok, port, python_pid} ->
        state = %__MODULE__{
          port: port,
          python_pid: python_pid,
          pending_requests: %{},
          request_counter: 0
        }

        # Send initialization ping
        case send_ping(state) do
          {:ok, new_state} ->
            {:ok, new_state, timeout}

          {:error, reason} ->
            {:stop, {:initialization_failed, reason}}
        end

      {:error, reason} ->
        {:stop, {:failed_to_start_bridge, reason}}
    end
  end

  @impl true
  def handle_call({:execute, command, args, timeout}, from, state) do
    request_id = state.request_counter + 1

    # Validate with adapter
    case SnakepitDspy.Adapter.validate_command(command, args) do
      :ok ->
        prepared_args = SnakepitDspy.Adapter.prepare_args(command, args)
        request = Protocol.encode_request(request_id, command, prepared_args)

        try do
          Port.command(state.port, request)
          # Track the request
          pending = Map.put(state.pending_requests, request_id, {from, command})
          new_state = %{state | pending_requests: pending, request_counter: request_id}

          # Set timeout
          Process.send_after(self(), {:request_timeout, request_id}, timeout)

          {:noreply, new_state}
        catch
          :error, _ ->
            {:reply, {:error, :port_command_failed}, state}
        end

      {:error, reason} ->
        {:reply, {:error, {:validation_failed, reason}}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case Protocol.decode_response(data) do
      {:ok, request_id, result} ->
        handle_response(request_id, {:ok, result}, state)

      {:error, request_id, error} ->
        handle_response(request_id, {:error, error}, state)

      other ->
        Logger.error("Invalid response from DSPy bridge: #{inspect(other)}")
        {:noreply, state}
    end
  end

  def handle_info({:request_timeout, request_id}, state) do
    case Map.pop(state.pending_requests, request_id) do
      {{from, _command}, new_pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending_requests: new_pending}}

      {nil, _} ->
        # Request already completed
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Logger.error("DSPy bridge port exited: #{inspect(reason)}")
    {:stop, {:port_exited, reason}, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Direct worker received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Direct DSPy worker terminating: #{inspect(reason)}")

    if state.port && Port.info(state.port) do
      Port.close(state.port)
    end

    :ok
  end

  # Private Functions

  defp execute_command(worker, command, args, timeout) do
    GenServer.call(worker, {:execute, command, args, timeout}, timeout + 1000)
  end

  defp start_python_bridge do
    python_path = System.find_executable("python3") || System.find_executable("python")
    script_path = SnakepitDspy.Adapter.script_path()
    script_args = SnakepitDspy.Adapter.script_args()

    port_opts = [
      :binary,
      :exit_status,
      {:packet, 4},
      {:args, [script_path] ++ script_args}
    ]

    try do
      port = Port.open({:spawn_executable, python_path}, port_opts)

      python_pid =
        case Port.info(port, :os_pid) do
          {:os_pid, pid} -> pid
          _ -> nil
        end

      {:ok, port, python_pid}
    rescue
      e -> {:error, e}
    end
  end

  defp send_ping(state) do
    request_id = 1
    request = Protocol.encode_request(request_id, "ping", %{"initialization" => true})

    try do
      Port.command(state.port, request)
      # Wait for ping response
      receive do
        {port, {:data, data}} when port == state.port ->
          case Protocol.decode_response(data) do
            {:ok, ^request_id, _response} ->
              {:ok, %{state | request_counter: request_id}}

            error ->
              {:error, error}
          end
      after
        10_000 ->
          {:error, :ping_timeout}
      end
    catch
      :error, _ ->
        {:error, :port_command_failed}
    end
  end

  defp handle_response(request_id, result, state) do
    case Map.pop(state.pending_requests, request_id) do
      {{from, command}, new_pending} ->
        # Process response through adapter if needed
        final_result =
          case result do
            {:ok, response} ->
              SnakepitDspy.Adapter.process_response(command, response)

            error ->
              error
          end

        GenServer.reply(from, final_result)
        {:noreply, %{state | pending_requests: new_pending}}

      {nil, _} ->
        Logger.warning("Received response for unknown request: #{request_id}")
        {:noreply, state}
    end
  end
end
