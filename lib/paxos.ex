defmodule Paxos do

  @moduledoc """
  An Abortable Paxos implementation, as described in Leslie Lamport's "Paxos
  Made Simple" paper.
  """
  require Macros
  require Logger

  # State for the current module.
  # This is a struct that may be initialized with either the name of the
  # current module, i.e., %Paxos{}, or for more flexibility, the __MODULE__
  # compilation environment macro may be used, i.e., %__MODULE__{}.

  @enforce_keys [:name, :participants, :acceptances, :max_bal]
  defstruct [
    # IPC fundamentals -- what is this Paxos process called? which other Paxos
    # processes does this one talk to?
    :name, :participants, :acceptances, :max_bal
  ]

  # ---------------------------------------------------------------------------
  @doc """
  Starts a delegate instance of the abortable Paxos implementation. Name is an
  alias provided to refer to the **Paxos implementation**.
  The list of participants for Paxos, is (naturally) specified by participants.
  """

  def start(name, participants) do
    if not Enum.member?(participants, name) do
      Logger.error("The Paxos process is not in its own participants list.", [data: [process: name, participants: participants]])
      nil
    else
      # Spawn a process, call Paxos.init with the specified parameters.
      pid = spawn(
        Paxos, :init,
        [name, participants]
      )
      # Register the specified name, (or re-register if it already exists).
      :global.re_register_name(name, pid)
      Process.register(pid, name)
      Logger.info("Spawned Paxos instance.", [data: [name: name]])
      # Return the process ID of the spawned Paxos instance.
      pid
    end
  end

  @doc """
  Initializes a process as a Paxos delegate process by creating the necessary
  structures, starting an underlying BestEffortBroadcast instance for that
  process and then starting a run-state loop to handle incoming Paxos requests.
  """

  def init(name, participants) do
    # Wait a tiny delay before initializing to allow this process to be
    # registered by the caller before it is used.
    Process.sleep(10)
    Logger.info("Paxos delegate initializing...")
    # Initialize BestEffortBroadcast for this process.
    BestEffortBroadcast.start()
    # Initialize the state and begin the run-state loop.
    state = %Paxos{
      name: name,
      participants: participants,
      acceptances: %{},
      max_bal: 0
      # ...
    }
    run(state)
  end

  @spec propose(atom | pid | port | reference | {atom, atom}, any, any, any) ::
          nil | :timeout | tuple
  @doc """
  Propose a given value, value, for the instance of consensus associated with
  instance_number.
  """

  def propose(delegate, instance_number, value, timeout) do
    {_, _, _, _, result} = rpc_paxos(
      # Deliver, to delegate, the following message:
      delegate, {__MODULE__, :propose, instance_number, self(), {value, timeout}},
      # After timeout, return the default of :timeout.
      timeout
    )
    result
  end

  @doc """
  Returns the value decided by the consensus associated with instance_number,
  if there was one. Otherwise, returns nil. Also returns nil on timeout.
  """

  def get_decision(delegate, instance_number, timeout) do
    {_, _, _, _, result} = rpc_paxos(
      # Deliver, to delegate, the following message:
      delegate, {__MODULE__, :get_decision, instance_number, self(), {timeout}},
      # After timeout, return nil.
      timeout, nil
    )
    result
  end

  # -----------------------
  # END OF PUBLIC INTERFACE
  # -----------------------

  @doc """
  We need to propose using beb to all processes
  Return the result from propose
  """

  defp paxos_propose(state, instance_number, client, {value, timeout}) do
    BestEffortBroadcast.broadcast(state.participants, {:proposal, value, instance_number})
  end

  defp paxos_get_decision(state, instance_number, client, {timeout}) do

  end

  # We get the initial proposals back, but message is taken out of value. try and pass the whole value through beb.

  defp run(state) do
    state = receive do
      {:proposal, value, instance_number} ->
        # We need to implement our ballot check here to before proceeding, to satisfy P2C
        # P1: "process must accept first proposal it gets"
        # Has instance of consensus for this process of paxos accepted a value
        if (!Map.has_key?(state.acceptances, instance_number)) do
          Logger.info("NO ACCPETANCE FOR INSTANCE", [data: [instance_number: instance_number, value: value]])
          %{state | acceptances: Map.put(state.acceptances, instance_number, value)}
        else
          # Already accepted a value
          Logger.info("INSTANCE ALREADY MADE ACCEPTANCE", [data: [instance_number: instance_number, value: value]])
          state
        end

      {__MODULE__, command, instance_number, client, arguments} ->
        # Handle pre-set commands specified with the Paxos implementation
        # protocol by executing the appropriate handler function.
        IO.puts("__MODULE__, command, instance_number, client, arguments")
        IO.puts("#{inspect(state)}")
        result = case command do
          :propose -> paxos_propose(state, instance_number, client, arguments)
          :get_decision -> paxos_get_decision(state, instance_number, client, arguments)
        end
        # Send the reply yielded from executing a command back to the client,
        # again with the Paxos implementation protocol.
        send(client, {__MODULE__, command, instance_number, client, result})
        state
    end
    run(state)
  end

  # # Used to execute an RPC to some target process, and get a response, within
  # # some time frame. After the time frame has expired, :timeout is returned
  # # instead.
  # defp rpc_raw(target, message, timeout) do
  # # Send the message to the delegate.
  #   send(target, message)
  #   # Wait for a reply that satisfies the conditions (number of header values
  #   # matching).
  #   receive do
  #     reply -> reply
  #   after timeout -> :timeout
  #   end
  # end
  # Used by calling process (i.e., a client) to execute a remote procedure call
  # to a Paxos delegate, and get a response.
  # We match 3 header elements (module, command, Paxos instance number).
  # This ensures that we only process, as a reply, messages relevant to those
  # header elements.

  defp rpc_paxos(delegate, message, timeout, value_on_timeout \\ :timeout) do

      # Send the message to the delegate.
    send(delegate, message)

    # Wait for a reply that satisfies the conditions (number of header values
    # matching = 3).

    receive do
      reply when Macros.matching_tuple_values(3, reply, message) -> reply

    # Or alternatively, time out.

    after timeout -> value_on_timeout
    end
  end

  # -----------------------
  # DEBUG INTERFACE
  # -----------------------

end
