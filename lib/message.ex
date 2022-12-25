defmodule Message do

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
    command,
    payload,
    metadata,
    other_arguments \\ (quote do (%{reply_to: nil}) end)
  ) do
    quote do: ({
      :encrypted,
      Crypto.encrypt(unquote(metadata).key,
        :erlang.term_to_binary(%{
          message: Message.pack(
            unquote(command),
            unquote(payload),
            unquote(other_arguments)
          ),
          challenge_response: Crypto.solve_challenge(unquote(metadata).key, unquote(metadata).challenge)
        })
      )
    })
  end

end
