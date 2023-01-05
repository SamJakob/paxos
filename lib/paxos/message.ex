defmodule Paxos.Message do

  require Paxos.Crypto

  defmacro pack(
    command,
    payload,
    other_arguments \\ (quote do (%{reply_to: nil}) end)
  ) do
    quote do: (Map.merge(%{
      protocol: __MODULE__,
      command: unquote(command),
      instance_number: var!(instance_number),
      payload: unquote(payload)
    }, unquote(other_arguments)))
  end

  defmacro pack_encrypted(
    rpc_id,
    command,
    payload,
    metadata,
    other_message_arguments \\ (quote do (%{reply_to: nil}) end)
  ) do
    quote do: ({
      :encrypted,
      unquote(rpc_id),
      Paxos.Crypto.encrypt(unquote(metadata).key,
        :erlang.term_to_binary(%{
          message: Paxos.Message.pack(
            unquote(command),
            unquote(payload),
            unquote(other_message_arguments)
          ),
          challenge_response: Paxos.Crypto.solve_challenge(unquote(metadata).key, unquote(metadata).challenge)
        })
      )
    })
  end

end
