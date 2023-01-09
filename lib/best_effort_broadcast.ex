defmodule Paxos.BestEffortBroadcast do
  @moduledoc """
  A Best-Effort broadcast implementation.
  This is based on the version provided for the formative coursework with
  changes made for readability, versatility and robustness.

  This implementation differs in that it requires minimal external
  configuration, additionally it differs from the ordinary pattern/architecture
  for modules in that its entry point is entirely booted from an external
  process. This is to reduce complexity in what is otherwise merely a
  convenience module.
  """

  # State for the current module.
  # This is a struct that may be initialized with either the name of the current
  # module, i.e., %Paxos.BestEffortBroadcast{}, or for more flexibility, the
  # __MODULE__ compilation environment macro may be used, i.e., %__MODULE__{}.

  @enforce_keys [:client, :failed, :broadcast_type]
  defstruct [:client, :failed, :broadcast_type]

  # ---------------------------------------------------------------------------

  # Convenience attribute to specify the default behavior of a failed link.
  # Setting this to true mandates that a failed link send at least one message.
  # Setting this to false, allows for a failed link to not send any message at
  # all.
  # Wherein, failed links refers to links that, for the sake of debugging, are
  # simulating failure.
  @failedLinksStillSend true

  @doc """
  Starts an instance of the BestEffortBroadcast module by creating a delegate
  process and setting it up with the default state (no failures, nominal
  broadcast type.)

  (An external process would call this function to set up an instance of
  BestEffortBroadcast for itself.)

  Returns the PID of the delegate process.
  """
  def start do
    delegate = spawn(__MODULE__, :run, [%__MODULE__{
      client: self(),
      failed: false,
      broadcast_type: :nominal,
    }])

    Process.put("#{__MODULE__}/default_beb_delegate", delegate)
    delegate
  end

  @doc """
  Sends a broadcast request to the default BestEffortBroadcast delegate for the
  calling process.

  Example usage:
  Paxos.BestEffortBroadcast.broadcast([:p1, :p2], {:hello, "world"})
  """
  def broadcast(targets, message) do
    case Process.get("#{__MODULE__}/default_beb_delegate") do
      nil -> {__MODULE__, :error, message, targets, "Failed to locate default #{__MODULE__} delegate for process #{self()}! Do you need to specify a PID?"}
      pid -> broadcast(pid, targets, message)
    end
  end

  @doc """
  Similar to broadcast/2 but also requires the delegate PID to be specified
  instead of retrieved from the process dictionary.

  Example usage:
  Paxos.BestEffortBroadcast.broadcast(pid, [:p1, :p2], {:hello, "world"})
  """
  def broadcast(delegate, targets, message) do
    send(delegate, {__MODULE__, :broadcast, targets, message})
  end

  # The run-state loop. This will execute circularly with tail-end recursion to
  # accept new requests for best-effort broadcasts between processes.
  #
  # The use of this run-state loop takes advantage of Elixir's built-in
  # mailboxes for IPC, enabling the process to enqueue requests if it becomes
  # inundated and process them when it can.
  def run(state) do
    state = receive do
      {__MODULE__, :broadcast, targets, message} ->
        handle_broadcast_request(
          state,
          (if not state.failed, do: targets, else: randomly_drop(targets)),
          message
        )

      {__MODULE__, :ping, pid} ->
        send(state.client, {__MODULE__, :pong, pid})
        state

      {__MODULE__, :debug_set_failed} ->
        %{state | failed: true}

      {__MODULE__, :debug_set_broadcast_type, type} ->
        %{state | type: type}
    end

    # If the process has failed or crashed, exit the best effort broadcast
    # process.
    if state.failed do
      Process.exit(self(), :kill)
    end

    # Perform next iteration of run-state loop.
    run(state)
  end


  # -----------------------
  # END OF PUBLIC INTERFACE
  # -----------------------

  # The following methods are used for debugging implementations. THEY ARE NOT
  # intended for ordinary use, and as such, all of their names are prefaced
  # with debug_.

  def debug_fail(pid) do
    send(pid, {__MODULE__, :debug_set_failed})
  end

  # Debugging method used to configure the simulated type (or state) of links
  # used. Implemented modes are as follows:
  #   :nominal (do not introduce additional behavior)
  #   :reordered (randomize the order and delay after which messages are delivered)
  def debug_change_broadcast_type(pid, type \\ :nominal) do
    send(pid, {__MODULE__, :debug_set_broadcast_type, type})
  end

  # Debugging method used to instantly crash the BEB process.
  def debug_crash do
    Process.exit(self(), :kill)
  end


  # -----------------------
  # END OF DEBUG INTERFACE
  # -----------------------

  # The following methods are private and implementation-dependent ONLY. THEY
  # MUST NOT be accessible to code outside of this module.

  # Delivers a message to the specified target over a point-to-point link.
  defp unicast(state, target, message) do
    case :global.whereis_name(target) do
      pid when is_pid(pid) -> send(pid, message)
      :undefined ->
        send(state.client, {__MODULE__, :error, message, target, "Process #{target} not found!"})
        {__MODULE__, :error, message, target, "Process #{target} not found!"}
    end
  end

  # Implements a broadcast primitive for the Best Effort Broadcast
  # implementation to wrap that simply unicasts the specified message to each
  # of the targets.
  defp broadcast_primitive(state, targets, message) do
    for target <- targets, do: unicast(state, target, message)
  end

  defp randomly_drop(values, ensure_at_least_one \\ @failedLinksStillSend) do
    # Shuffle the values to ensure any value has an equally random chance of
    # being dropped (otherwise the first value would be disproportionately
    # favored.)
    # Then select either:
    #   (ensure_at_least_one = true) 1 or more processes to send the message
    #                                to.
    #   (otherwise) 0 or more processes to send the message to.
    Enum.slice(Enum.shuffle(values), 0, Enum.random(
      (if ensure_at_least_one, do: 1, else: 0)..length(values)
    ))
  end

  # Implements the application logic for handling a broadcast request when
  # the broadcast type is configured to simulate out-of-order messaging.
  defp handle_broadcast_request(state, targets, message) when state.broadcast_type == :reordered do
    spawn(fn ->
      Process.sleep(Enum.random(1..250))
      broadcast_primitive(state, targets, message)
    end)

    state
  end

  # Fallback for application logic to handle a broadcast request where no
  # recognized special circumstances were specified.
  defp handle_broadcast_request(state, targets, message) do
    broadcast_primitive(state, targets, message)
    state
  end
end
