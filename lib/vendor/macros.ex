defmodule Macros do
  defmacro matching_tuple_values(n, a, b) do
    # If we've reached n = 0 for the Macro invocation, we've already checked
    # the elements at that index, so we can
    if n < 1, do: true,
    else: quote do: (
      # Check that elem(a, n - 1) == elem(b, n - 1).
      (elem(unquote(a), unquote(n) - 1) == elem(unquote(b), unquote(n) - 1))
      # Then, check that this also holds recursively for
      # matching_tuple_values(n - 1, ...).
      and unquote(__MODULE__).matching_tuple_values(unquote(n - 1), unquote(a), unquote(b))
    )
  end

  defmacro pack_message(
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
end
