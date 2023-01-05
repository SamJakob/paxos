#!/usr/bin/env bash

# Simple build script to combine all source files into one flat Elixir script.

SOURCE_FILES="lib/"
OUTPUT_DIRECTORY="dist/"
OUTPUT_FILE="paxos.ex"
DEPENDENCY_DIRECTORY="deps/"

DEPENDENCIES=( typed_struct uuid )

### Script start
# Define a function that may be used to recursively add code in .ex files
# from a directory.
function add_code {
  find "$1" -type f -name "*.ex" -exec printf "###########\n# $3\n# {}\n###########\n" >> "$2" \; -exec cat "{}" >> "$2" \; -exec printf "\n\n" >> "$2" \;
}

# Create output directory
[ -d "$OUTPUT_DIRECTORY" ] && rm -r "$OUTPUT_DIRECTORY"
mkdir "$OUTPUT_DIRECTORY"

DESTINATION="$OUTPUT_DIRECTORY$OUTPUT_FILE"

echo "# paxos.ex" > "$DESTINATION"
echo "# Generated on $( date "+%b. %d, %Y" ) at $( date "+%I:%M:%S %p" )" >> "$DESTINATION"
echo "" >> "$DESTINATION"

# Scan dependencies and append to OUTPUT_FILE
for dependency in "${DEPENDENCIES[@]}"; do
  echo "Adding dependency $dependency"
  add_code "$DEPENDENCY_DIRECTORY$dependency/lib" "$DESTINATION" "Type: Mix Dependency ($dependency)"
done

echo "Adding Paxos project code"
add_code "$(echo "$SOURCE_FILES" | sed 's:/*$::')" "$DESTINATION" "Type: Project Code"

echo "Postprocessing file..."
sed '/^[[:space:]]*@external_resource/d' dist/paxos.ex > dist/paxos.ex.new
mv dist/paxos.ex.new dist/paxos.ex

sed '/@moduledoc "README.md"/,/Enum.fetch!(1)/d' dist/paxos.ex > dist/paxos.ex.new
mv dist/paxos.ex.new dist/paxos.ex
