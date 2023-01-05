defmodule Paxos.Crypto do

  @magicAuthenticationPayload "AB"

  @doc """
  Generates a unique base-64 value of the requested length in bytes
  (default = 64).
  """
  def unique_value(length \\ 64) do
    Base.encode64(:crypto.strong_rand_bytes(length))
  end

  @doc """
  Generates an AES-256 key.
  """
  def generate_key() do
    :crypto.strong_rand_bytes(32)
  end

  @doc """
  Encrypts the payload using the specified key. The value returned is just the
  encrypted payload which may be sent and subsequently used for decryption.
  """
  def encrypt(key, payload) do
    iv = :crypto.strong_rand_bytes(16)

    {cipher_text, cipher_tag} = :crypto.crypto_one_time_aead(
      :aes_256_gcm,
      key, iv, payload,

      # Authentication Data
      @magicAuthenticationPayload,

      # isEncrypting: true = encrypt, false = decrypt
      true
    )

    {iv, cipher_text, cipher_tag}
  end

  @doc """
  Unpacks and decrypts the payload using the specified key, returning the
  result.
  """
  def decrypt(key, payload) do
    {iv, cipher_text, cipher_tag} = payload

    :crypto.crypto_one_time_aead(
      :aes_256_gcm,
      key, iv,
      cipher_text, @magicAuthenticationPayload, cipher_tag,
      false
    )
  end

  @doc """
  Generates a challenge and a solution.

  The solution SHOULD NOT be shared. Doing so might introduce a risk of opening
  up replay attacks.

  Use of a challenge-response means that once the key has been distributed to
  both parties, that key can continue to be re-used without enabling replay
  attacks (provided, obviously that the challenge is instead changed on a
  per-request basis).

  This implementation uses AES-GCM which also verifies message integrity
  through the message authentication tag (integrity check value, ICV). This
  means we can be assured that the message has also not been manipulated in
  transit.
  """
  def create_challenge(key) do
    # Choose a large random integer to serve as a numerator and an always
    # small random integer to serve as divisor.
    challenge = 1001 + random_integer(576460752303422487)
    divisor = 2 + random_integer(7) # Random integer between 3 and 9
                                    # (as l.b. is 1).

    # Solve the problem with integer division.
    solution = div(challenge, divisor)

    # Encrypt the result - this is the challenge.
    challenge = encrypt(key, Integer.to_string(challenge) <> "/" <> Integer.to_string(divisor))

    # Return the challenge and the solution.
    {challenge, solution}
  end

  @doc """
  The implementation necessary to solve a challenge, given a valid key.
  To be solved by the party attempting to prove themselves. The goal here is to
  prove possession of the key.
  """
  def solve_challenge(key, challenge) do
    # Decrypt challenge using key.
    value = decrypt(key, challenge)

    # Parse and solve the challenge.
    parts = String.split(value, "/", trim: true)
    numerator = String.to_integer(Enum.at(parts, 0))
    denominator = String.to_integer(Enum.at(parts, 1))
    solution_attempt = div(numerator, denominator)

    # Then encrypt the result.
    encrypt(key, Integer.to_string(solution_attempt))
  end

  @doc """
  Verifies that the challenge has been successfully solved, by checking that
  the response to the challenge is, indeed, an encrypted form of the solution.
  Returns true if the challenge was solved correctly, otherwise false.
  """
  def verify_challenge_response(key, response, solution) do
    # Decrypt response with key and compare to solution.
    attempted_solution = decrypt(key, response)
    String.to_integer(attempted_solution) == solution
  end

  defp random_integer(max) do
    # Ensure the random number generator has been cryptographically seeded.
    :crypto.rand_seed()
    :rand.uniform(max)
  end

end
