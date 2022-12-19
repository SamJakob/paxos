# Paxos

An Abortable Παξος Implementation for Consensus based on Leslie Lamport's
paper, "Paxos Made Simple".

## Running with IEx
Simply use:
```bash
iex -S mix
```

(or, alternatively, on Windows Powershell):
```powershell
iex.bat -S mix
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `paxos` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:paxos, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/paxos>.

