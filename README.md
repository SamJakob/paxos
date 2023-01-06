# Paxos

An Abortable Παξος Implementation for Consensus based on Leslie Lamport's
paper, "Paxos Made Simple".

Requires Elixir >= 1.13 and OTP >= 23.

> This multi-file setup using Mix is currently broken when run in the
> Vagrant testing VM on Windows. Please instead refer to the single-file
> built by [/build.sh](/build.sh).

## Setup
- Install mix dependencies with `mix deps.get`.
- Run tests with `iex -S mix run test/test_script.exs`
  - Alternatively, silence extraneous output from test scripts with:
  `iex -S mix run test/test_script.exs > /dev/null`
  - Or to run tests, whilst logging results into a file and to the console, use:
  `iex -S mix run test/test_script.exs 2>&1 >/dev/null | tee results.txt`

### Using the original test files
To support using `Mix` to compile the project, the test files were slightly
modified, to perform these changes, please do the following:
1. Update `test_with_mix/test_harness.ex` to include files compiled by Mix.
    1. Modify line 54, to include ` -S mix` at the end.
    2. The line should now appear as follows:
    ```elixir
    cmd = "elixir --sname " <> (hd String.split(Atom.to_string(node), "@")) <> " --no-halt --erl \"-detached\" --erl \"-kernel prevent_overlapping_partitions false\" -S mix"
    ```

2. Comment out `uuid.ex` from `test_script.exs` as it's included in the project
   and thus compiled by mix (also make sure the project files are commented out
   as these are also included by Mix).  
   The start of `test_script.exs` should now appear as follows:
   ```elixir
    # Replace with your own implementation source files
    # IEx.Helpers.c "beb.ex", "."
    # IEx.Helpers.c "paxos.ex", "."
    
    # Do not modify the following ##########
    IEx.Helpers.c "test_with_mix/test_harness.ex", "."
    IEx.Helpers.c "test_with_mix/paxos_test.ex", "."
    IEx.Helpers.c "test_with_mix/test_util.ex", "."
    # IEx.Helpers.c "uuid.ex", "."
   ```

## Notes
- For debugging/presentation purposes, `Logger.flush()` has been included
frequently (for coherent log presentation). These MUST be removed before
production - particularly if the Console backend is not to be used!

## Running with IEx
Simply use:
```bash
iex -S mix

# (or)
iex -S "mix" "run" "example_commands.exs"
```

(or, alternatively, on Windows Powershell):
```powershell
iex.bat -S mix

# (or)
iex.bat -S "mix" "run" "example_commands.exs"
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

