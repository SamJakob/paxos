defmodule Paxos do

  @moduledoc """
  An Abortable Paxos implementation, as described in Leslie Lamport's "Paxos
  Made Simple" paper.
  """

  use TypedStruct
  require Message
  require Logger

  # State for the current module.
  # This is a struct that may be initialized with either the name of the
  # current module, i.e., %Paxos{}, or for more flexibility, the __MODULE__
  # compilation environment macro may be used, i.e., %__MODULE__{}.

  typedstruct enforce: true do
    field :name, atom()
    field :participants, list(atom())

    field :current_ballot, integer(), default: 0

    # The previously accepted ballot. Initially the ballot number is 0 which
    # means accept whatever the current proposal is (hence the previously
    # accepted ballot value, here, is nil by default.)
    field :accepted, {integer(), any()}, default: {0, nil}

    # A map of instance number to a proposal made for that instance number.
    # This will only hold that value if the proposal was made to this process
    # and thus this process created a ballot for it - at this time, it is
    # anticipated that any given process will only handle one ballot at once.
    # (i.e., if this process is the leader.)
    field :ballots,
      %{required(integer()) => %{
        :proposer => pid(),
        :value => any()
      }},
      default: %{}

    # Used to store encryption keys for RPC calls.
    field :keys, %{required(String.t()) => any()}, default: %{}
  end

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
        [name, participants, self()]
      )

      # Register the specified name, (or re-register if it already exists).
      try do
        :global.re_register_name(name, pid)
        Process.register(pid, name)

        # Sleep for a tiny amount of time (10ms) to allow the registration to
        # propagate across the system.
        Process.sleep(10)

        # Registration was successful. Now tell the process it can boot.
        send(pid, :raw_signal_startup)

        # Allow some time for the process to have initialized.
        # This does nothing except potentially make the logs cleaner in
        # interactive mode.
        receive do
          # Process is confirmed to be alive, continue and return PID.
          :raw_signal_startup_complete ->
            Logger.info("Successfully initialized Paxos instance.", [data: [name: name]])

            # Return the process ID of the spawned Paxos instance.
            Logger.flush()
            pid

          # Process has confirmed abort. It should kill itself and we can just
          # return nil.
          :raw_signal_startup_aborted ->
            nil

          # If the process has totally hung or become unresponsive, we will
          # attempt to kill the process.
          after 5000 ->
            if Process.alive?(pid) do
              Logger.error("Paxos delegate initialization timed out. Aborting.")

              # Process failed to acknowledge startup and is now orphaned so
              # attempt to kill it.
              Process.exit(pid, :killed_orphaned)
            end

            # Return nothing.
            nil
        end
      # Intercept problems to attempt to kill the process gracefully.
      rescue e ->
        send(pid, :raw_signal_kill)
        raise e
      end
    end
  end

  @doc """
  Initializes a process as a Paxos delegate process by creating the necessary
  structures, starting an underlying BestEffortBroadcast instance for that
  process and then starting a run-state loop to handle incoming Paxos requests.
  """
  def init(name, participants, spawner) do
    # Wait for the spawning process to signal that this one can be booted
    # (i.e., that everything has been registered.)
    Logger.info("Waiting for initialize signal...")

    can_continue = receive do
      # If we get the signal / 'go ahead' to initialize, log and then continue.
      :raw_signal_startup ->
        Logger.info("Initializing...")
        :yes
      # Arbitrary kill signal (i.e., external registration failed).
      :raw_signal_kill ->
        Logger.info("Aborted startup.")
        send(spawner, :raw_signal_startup_aborted)
        :no
      # Timeout whilst confirming initialize. Process cannot be registered.
      after 1000 ->
        Logger.error(
          "Timed out whilst waiting for initialize signal. (Did the process fail to register?)"
        )
        :no
    end

    if can_continue == :yes do
      # Now we can begin to initialize and boot this process.
      # Initialize BestEffortBroadcast for this process.
      BestEffortBroadcast.start()

      # Initialize the state and begin the run-state loop.
      state = %Paxos{
        name: name,
        participants: participants
      }

      Logger.notice("Ready! Listening as #{name} (#{inspect(self())}).")
      send(spawner, :raw_signal_startup_complete)
      run(state)
    end
  end

  @doc """
  Propose a given value, value, for the instance of consensus associated with
  instance_number.
  """
  def propose(delegate, instance_number, value, timeout) do
    result = rpc_paxos(
      # Deliver, to delegate, the following message:
      delegate, Message.pack(:propose, {value}, %{reply_to: self()}),
      # After timeout, return the default of :timeout.
      timeout
    )

    Logger.flush()
    result
  end

  @doc """
  Returns the value decided by the consensus associated with instance_number,
  if there was one. Otherwise, returns nil. Also returns nil on timeout.
  """
  def get_decision(delegate, instance_number, timeout) do
    rpc_paxos(
      # Deliver, to delegate...
      delegate,
      # the following message:
      Message.pack(:get_decision, {timeout}, %{reply_to: self()}),
      # After timeout, return nil.
      timeout, nil
    )
  end

  @doc """
  Adds the specified key to the delegate and returns the newly created ID for
  that key. This ID should not be shared.

  Presently, this just relies on MITM starting after the keys are exchanged
  (which for demonstration purposes is kind of a daft assumption given that the
  keys are exchanged every time an RPC occurs) but in a production system, the
  key-exchange could be done on startup to minimize the MITM window. And, to
  beef this up further, PKI could be utilized to rely on asymmetric keys for
  key exchange first which would (in a good PKI implementation) eliminate or
  reduce to negligible concern the risk of MITM.
  """
  def add_key(delegate, key, timeout \\ 5000) do
    response = rpc_raw(delegate, %{
      protocol: __MODULE__,
      command: :add_key,
      reply_to: self(),
      payload: %{
        key: key
      }
    }, timeout)

    # If we got a map back, it worked successfully, so return the key ID,
    # otherwise, return the error tuple.
    if is_map(response), do: response.key, else: response
  end

  # TODO: protect key?
  @doc """
  Deletes the specified key (id) from the delegate.
  """
  def delete_key(delegate, key, timeout \\ 5000) do
    response = rpc_raw(delegate, %{
      protocol: __MODULE__,
      command: :delete_key,
      reply_to: self(),
      payload: %{
        key: key
      }
    }, timeout)

    # If we get a map back, there's no useful information, it worked as
    # intended. Otherwise, there's an error so return it directly.
    if is_map(response), do: nil, else: response
  end


  # TODO: protect key?
  @doc """
  Checks if the specified key (id) is held by the delegate.
  Returns true or false.
  """
  def has_key(delegate, key, timeout \\ 5000) do
    response = rpc_raw(delegate, %{
      protocol: __MODULE__,
      command: :delete_key,
      reply_to: self(),
      payload: %{
        key: key
      }
    }, timeout)

    if is_map(response), do: response.is_held, else: response
  end

  # -----------------------
  # END OF PUBLIC INTERFACE
  # -----------------------

  # ---------------------------------------------------------------------------

  # Paxos.propose - Step 1 of 1 - Leader
  # Create a new ballot, b.
  # Broadcast (prepare, b) to all processes.
  defp paxos_propose(state, instance_number, reply_to, {value}, metadata) do
    BestEffortBroadcast.broadcast(
      state.participants,
      Message.pack(
        # -- Command
        :prepare,

        # -- Data
        # We prepare the next ballot (after the current one) for voting on.
        %{ballot: state.current_ballot + 1, value: value},

        # -- Additional Options
        # Send replies to :prepare to the Paxos delegate - not the client.
        %{reply_to: self()}
      )
    )

    # Add this proposal to the list of ballots this leader is currently
    # working on.
    state = %{state
      | ballots: Map.put(
        state.ballots, instance_number,
        %{proposer: reply_to, value: value, metadata: metadata}
      )
    }

    # We won't reply to the propose request immediately. Instead, we will
    # handle this internally and send the reply when we're ready, elsewhere.
    # Returning from this RPC with :skip_reply means we won't send the reply
    # and thus the requestor will continue to wait for a reply (either until
    # it gets one, or until it times out.)
    %{result: :skip_reply, state: state}
  end

  # Paxos.propose - Step 2 of 2 - All Processes
  # Check if the incoming ballot is greater than the current one. If it is,
  # send :prepared to reply_to.
  # Otherwise, send :nack.
  defp paxos_prepare(state, instance_number, reply_to, %{ballot: ballot}) do
    if ballot > state.current_ballot do
      # If the new ballot is greater than any current ballot, tell the leader
      # we're prepared to accept this as our current ballot and indicate to
      # ourselves that we've seen at least this ballot (if the ballot is later
      # rejected, unless we're the leader we don't care but we shouldn't be
      # able to re-prepare that ballot, so incrementing current_ballot here
      # is fine - if we are the leader, that logic is handled elsewhere, in the
      # other stages, anyway).
      send(reply_to, Message.pack(:prepared, %{
        ballot: ballot,
        accepted: state.accepted,
      }))
      %{
        result: :skip_reply,
        state: %{state | current_ballot: state.current_ballot + 1}
      }
    else
      # If we've already processed this ballot, or a ballot after this one, we
      # must not accept it and instead indicate that we've rejected it (i.e.,
      # not acknowledged, nack).
      send(reply_to, Message.pack(:nack, %{ballot: ballot}))
      %{result: :skip_reply, state: state}
    end
  end

  defp paxos_prepared(state, instance_number, %{accepted: _, ballot: ballot_number}) do
    with ballot when ballot != nil <- Map.get(state.ballots, instance_number) do

      # TODO: implement this.
      # return NACK for testing purposes.
      send(self(), Message.pack(:nack, %{ballot: ballot}))

      # If quorum reached, broadcast accept.

      # Else, store ballot and do nothing.
    else
      _ ->
        # This response is returned for future use, but currently will just be
        # thrown away. This is fine, we can safely disregard them - it's likely
        # that we aborted the ballot and other processes are catching up.
        {:error, "The requested proposal, instance #{instance_number}, ballot #{ballot_number}, could not be found. This process probably isn't the leader for this instance."}
    end

    :skip_reply
  end

  defp paxos_nack(state, instance_number, %{ballot: _}) do
    # If the instance_number is in the list of ballots we're currently
    # processing, then remove it and abort.
    state = if Map.has_key?(state.ballots, instance_number) do
      proposal = state.ballots[instance_number]
      state = %{state | ballots: Map.delete(state.ballots, instance_number)}

      # Return abort by replying to the client's propose message.
      send(
        proposal.proposer,
        Message.pack_encrypted(:propose, {:abort}, %{
          key: state.keys[proposal.metadata.key],
          challenge: proposal.metadata.challenge
        })
      )

      state
    end

    %{result: :skip_reply, state: state}
  end



  # Paxos.get_decision - Step 1 of 1
  # Returns the decision that was arrived at for the specified instance_number.
  defp paxos_get_decision(state, instance_number, reply_to, {}) do
    # TODO
    IO.puts("TODO -- get_decision -- #{state} #{instance_number} #{reply_to}")
  end


  # ---------------------------------------------------------------------------

  # The run-state loop.
  # Used to answer messages whilst keeping track of application state.
  defp run(state) do
    state = receive do
      message -> handle_message(state, message)
    end

    run(state)
  end

  defp handle_message_middlewares(state, message) do
    message = case message do
      {:encrypted, encrypted_payload, key_id} ->
        # Decrypt and decode the message and challenge using the requested key.
        %{message: message, challenge: challenge} = :erlang.binary_to_term(
          Crypto.decrypt(state.keys[key_id], encrypted_payload)
        )

        # Inject the key ID and challenge into the message as part of the
        # metadata.
        message = Map.merge(%{metadata: %{}}, message)
        %{message | metadata: Map.merge(message.metadata, %{key: key_id, challenge: challenge})}

      # In any case, if the message is a map, inject the metadata property.
      _ -> if is_map(message), do: Map.merge(%{metadata: %{}}, message), else: message
    end

    {state, message}
  end

  # Handles an incoming message by mutating the state and returning the updated
  # state. Additionally, checks if there are middlewares for this message and
  # processes them if there are by calling handle_message_middlewares/2.
  defp handle_message(state, message) do

    # Before we attempt to process the message, first check if there are
    # middlewares for this message that need to be executed.
    {state, message} = handle_message_middlewares(state, message)

    case message do
      # Paxos Commands
      %{
        # This block will only handle messages defined in the current module.
        protocol: __MODULE__,
        command: command,
        instance_number: instance_number,
        reply_to: reply_to,
        payload: payload,
        metadata: metadata
      } ->
        # Handle pre-set commands specified with the Paxos implementation
        # protocol by executing the appropriate handler function. Before we do,
        # we'll log the message for debugging purposes.
        Logger.debug("Received Paxos message.", [data: %{
          protocol: __MODULE__,
          command: command,
          instance_number: instance_number,
          reply_to: reply_to,
          payload: payload
        }])

        raw_result = case command do
          # Local State Control Commands (generally paxos_rpc)
          # --------------------------------------------------
          # A client process outside of the Paxos implementation issues these
          # requests to a Paxos delegate process (participant) with
          # Paxos.propose/4 or Paxos.get_decision/3, etc.,
          :propose -> paxos_propose(state, instance_number, reply_to, payload, metadata)
          :get_decision -> paxos_get_decision(state, instance_number, reply_to, payload)

          # Broadcast Commands (generally broadcasted)
          # ------------------------------------------
          # These are commands sent to other processes as part of the Paxos
          # processes (usually broadcasted).
          :prepare -> paxos_prepare(state, instance_number, reply_to, payload)
          :prepared -> paxos_prepared(state, instance_number, payload)
          :nack -> paxos_nack(state, instance_number, payload)

          # Fallback Handler
          # ----------------
          # If the command is unknown, this prevents a crash and instead
          # replies with a message indicating that the requested command was
          # unknown.
          _ ->
            Logger.warn("Received bad/unknown command, #{inspect command}.")
            {:error, "Bad/unknown command specified."}
        end

        # If a map containing just result and state is returned, interpret
        # result as the return value and state as the replacement state.
        # Otherwise, leave the state alone and just return whatever the
        # resulting value is.
        %{result: result, state: new_state} =
          if is_map(raw_result) and Map.keys(raw_result) -- [:result, :state] == [],
            do: raw_result,
            else: %{result: raw_result, state: nil}

        # Reflect the changes in the state, if there were any by the command
        # delegate.
        state = if new_state != nil, do: new_state, else: state

        # Send the reply yielded from executing a command back to the client,
        # again with the Paxos implementation protocol.
        if reply_to != nil and result != :skip_reply, do: send(
          reply_to,
          Message.pack(command, result)
        )

        # Finally, respond with the state.
        state

      # End Paxos Commands.

      # General Commands.
      # These commands are not directly related to the Paxos protocol, and are
      # instead used for additional functionality.
      %{
        protocol: __MODULE__,
        command: command,
        reply_to: reply_to,
        payload: payload,
        metadata: metadata
      } ->
        Logger.debug("Received general command.", [data: %{
          protocol: __MODULE__,
          command: command,
          reply_to: reply_to,
          payload: payload
        }])

        case command do
          :add_key ->

            # If the payload contains a key, accept the key, generate a unique
            # ID for it, and return the ID.

            if not Map.has_key?(payload, :key) do
              send(reply_to, %{ protocol: __MODULE__, command: command, payload: {:error, "Request missing attribute :key."} })
              state
            else
              # TODO: check if key itself already exists?

              # Recursively generate a new key ID until we arrive at a UUID not
              # already used as a key ID.
              # This should almost never recur, but we do this on the off chance
              # an implementation is dodgy or the 'impossible' happens to recover
              # gracefully.
              generate_new_key_id = fn
                recur -> uuid = UUID.uuid4()
                if Map.has_key?(state.keys, uuid),
                  do: recur.(recur),
                  else: uuid
              end

              key_id = generate_new_key_id.(generate_new_key_id)

              # Return a message with the ID to indicate success.
              send(reply_to, %{
                protocol: __MODULE__,
                command: command,
                payload: %{
                  key: key_id
                }
              })

              # Finally, write the key into storage.
              %{state | keys: Map.put(state.keys, key_id, payload.key)}
            end

          :delete_key ->

            # If the payload contains a key to drop, drop it, if it exists.
            if not Map.has_key?(payload, :key) do
              send(reply_to, %{ protocol: __MODULE__, command: command, payload: {:error, "Request missing attribute :key."} })
              # Leave state unaltered.
              state
            else

              if Map.has_key?(state.keys, payload.key) do
                # Return a message indicating that the key no longer exists by
                # reflecting the success message but where key is nil.
                send(reply_to, %{
                  protocol: __MODULE__,
                  command: command,
                  payload: %{
                    key: nil
                  }
                })

                %{state | keys: Map.delete(state.keys, payload.key)}
              else
                # Return an error message to indicate inability to find the
                # key.
                send(reply_to, %{
                  protocol: __MODULE__,
                  command: command,
                  payload: {:error, "The requested key could not be found."}
                })

                # Do nothing to state.
                state
              end

            end

          :has_key ->
            # If the payload contains a key to check, return the status of
            # whether the key is held.
            if not Map.has_key?(payload, :key) do
              send(reply_to, %{ protocol: __MODULE__, command: command, payload: {:error, "Request missing attribute :key."} })
            else
              send(reply_to, %{
                protocol: __MODULE__,
                command: command,
                payload: %{
                  is_held: Map.has_key?(state.keys, payload.key)
                }
              })
            end

            # Do nothing with the state.
            state
        end
      # End General Commands.

      error_message when is_tuple(error_message) and elem(error_message, 0) == :error ->
        Logger.warn("Received error message.", [data: error_message])
        state
    end

  end

  # ---------------------------------------------------------------------------

  # -----------------------
  # UTILITY METHODS
  # -----------------------

  # TODO: implement message counters for RPC?

  # Used to execute an unauthenticated, standard RPC to some target process,
  # and get a response, within some time frame. After the time frame has
  # expired, :timeout is returned instead.
  defp rpc_raw(target, message, timeout, value_on_timeout \\ {:timeout}) do
    # Send the message to the delegate.
    send(target, message)

    # Wait for a reply that satisfies the conditions, then return the payload
    # from the reply.
    receive do
      reply when
        reply.protocol == message.protocol and
        reply.command == message.command -> reply.payload

    # Or alternatively, time out.
    after timeout -> value_on_timeout
    end
  end

  # Used by calling process (i.e., a client) to execute a remote procedure call
  # to a Paxos delegate, and get a response.
  defp rpc_paxos(delegate, message, timeout, value_on_timeout \\ {:timeout}) do
    # Keys can be exchanged at any time (e.g., on startup/initialization), but
    # for demonstration purposes, they are exchanged here.
    key = Crypto.generate_key()

    # Send the key to the Paxos delegate for the lifecycle of this RPC.
    key_id = Paxos.add_key(delegate, key)

    # Create the challenge and solution.
    {challenge, solution} = Crypto.create_challenge(key)

    # Send the message to the delegate, encrypted and include the challenge.
    send(delegate, {:encrypted, Crypto.encrypt(key, :erlang.term_to_binary(%{
      message: message,
      challenge: challenge
    })), key_id})

    # Wait for a reply that satisfies the conditions, then return the payload
    # from the reply.
    receive do
      {:encrypted, encoded} ->
        %{
          message: reply,
          challenge_response: challenge_response
        } = :erlang.binary_to_term(Crypto.decrypt(key, encoded))

        # The key is no longer needed, it can be deleted from the Paxos
        # delegate.
        Paxos.delete_key(delegate, key_id)

        if (
          # Verify payload headers.
          reply.protocol == message.protocol and
          reply.command == message.command and
          reply.instance_number == message.instance_number and
          reply.reply_to == nil and
          # Verify challenge-response.
          Crypto.verify_challenge_response(key, challenge_response, solution)) do
            # If the reply checks out, return the payload.
            reply.payload
        else
          # Otherwise, return the timeout value.
          value_on_timeout
        end

    # Or alternatively, time out.
    after timeout -> value_on_timeout
    end
  end

  # ---------------------------------------------------------------------------

  # -----------------------
  # DEBUG INTERFACE
  # -----------------------

end
