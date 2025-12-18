defmodule JidoAI.Runner.GEPA.Crossover.Exchanger do
  @moduledoc """
  Implements component exchange strategies for crossover operations.

  This module provides three classic genetic algorithm crossover strategies:
  - **Single-Point**: Split at one point, swap halves
  - **Two-Point**: Split at two points, swap middle section
  - **Uniform**: Randomly select each segment from either parent

  ## Examples

      iex> {:ok, offspring} = Exchanger.single_point(parent_a, parent_b)
      iex> length(offspring)
      2

      iex> {:ok, offspring} = Exchanger.two_point(parent_a, parent_b)
      iex> length(offspring)
      2

      iex> {:ok, offspring} = Exchanger.uniform(parent_a, parent_b)
      iex> length(offspring)
      2
  """

  alias JidoAI.Runner.GEPA.Crossover.{PromptSegment, SegmentedPrompt}

  @doc """
  Performs single-point crossover on two segmented prompts.

  Selects a random crossover point and swaps all segments after that point.

  ## Parameters

  - `parent_a` - First segmented prompt
  - `parent_b` - Second segmented prompt
  - `opts` - Options:
    - `:crossover_point` - Specific point (default: random)
    - `:preserve_task` - Keep task description from parent_a (default: true)

  ## Returns

  - `{:ok, {offspring1, offspring2}}` - Two offspring prompts
  - `{:error, reason}` - If crossover fails

  ## Examples

      {:ok, {child1, child2}} = Exchanger.single_point(parent_a, parent_b)
  """
  @spec single_point(SegmentedPrompt.t(), SegmentedPrompt.t(), keyword()) ::
          {:ok, {String.t(), String.t()}} | {:error, term()}
  def single_point(parent_a, parent_b, opts \\ [])

  def single_point(
        %SegmentedPrompt{segments: segs_a} = parent_a,
        %SegmentedPrompt{segments: segs_b} = parent_b,
        opts
      )
      when length(segs_a) > 0 and length(segs_b) > 0 do
    preserve_task = Keyword.get(opts, :preserve_task, true)

    with {:ok, {aligned_a, aligned_b}} <- align_segments(segs_a, segs_b, preserve_task),
         crossover_point <- determine_crossover_point(aligned_a, opts),
         {first_a, second_a} <- Enum.split(aligned_a, crossover_point),
         {first_b, second_b} <- Enum.split(aligned_b, crossover_point) do
      offspring1_segments = first_a ++ second_b
      offspring2_segments = first_b ++ second_a

      offspring1 = reconstruct_prompt(offspring1_segments, parent_a)
      offspring2 = reconstruct_prompt(offspring2_segments, parent_b)

      {:ok, {offspring1, offspring2}}
    end
  end

  def single_point(_parent_a, _parent_b, _opts) do
    {:error, :invalid_parents}
  end

  @doc """
  Performs two-point crossover on two segmented prompts.

  Selects two random crossover points and swaps the middle section.

  ## Parameters

  - `parent_a` - First segmented prompt
  - `parent_b` - Second segmented prompt
  - `opts` - Options:
    - `:points` - Specific crossover points {p1, p2} (default: random)
    - `:preserve_task` - Keep task description from parent_a (default: true)

  ## Returns

  - `{:ok, {offspring1, offspring2}}` - Two offspring prompts
  - `{:error, reason}` - If crossover fails

  ## Examples

      {:ok, {child1, child2}} = Exchanger.two_point(parent_a, parent_b)
  """
  @spec two_point(SegmentedPrompt.t(), SegmentedPrompt.t(), keyword()) ::
          {:ok, {String.t(), String.t()}} | {:error, term()}
  def two_point(parent_a, parent_b, opts \\ [])

  def two_point(
        %SegmentedPrompt{segments: segs_a} = parent_a,
        %SegmentedPrompt{segments: segs_b} = parent_b,
        opts
      )
      when length(segs_a) >= 2 and length(segs_b) >= 2 do
    preserve_task = Keyword.get(opts, :preserve_task, true)

    with {:ok, {aligned_a, aligned_b}} <- align_segments(segs_a, segs_b, preserve_task),
         {point1, point2} <- determine_two_points(aligned_a, opts),
         {first_a, rest_a} <- Enum.split(aligned_a, point1),
         {middle_a, last_a} <- Enum.split(rest_a, point2 - point1),
         {first_b, rest_b} <- Enum.split(aligned_b, point1),
         {middle_b, last_b} <- Enum.split(rest_b, point2 - point1) do
      offspring1_segments = first_a ++ middle_b ++ last_a
      offspring2_segments = first_b ++ middle_a ++ last_b

      offspring1 = reconstruct_prompt(offspring1_segments, parent_a)
      offspring2 = reconstruct_prompt(offspring2_segments, parent_b)

      {:ok, {offspring1, offspring2}}
    end
  end

  def two_point(_parent_a, _parent_b, _opts) do
    {:error, :insufficient_segments}
  end

  @doc """
  Performs uniform crossover on two segmented prompts.

  For each segment position, randomly selects from either parent with 50% probability.

  ## Parameters

  - `parent_a` - First segmented prompt
  - `parent_b` - Second segmented prompt
  - `opts` - Options:
    - `:probability` - Probability of selecting from parent_a (default: 0.5)
    - `:preserve_task` - Keep task description from parent_a (default: true)
    - `:seed` - Random seed for reproducibility (default: nil)

  ## Returns

  - `{:ok, {offspring1, offspring2}}` - Two offspring prompts
  - `{:error, reason}` - If crossover fails

  ## Examples

      {:ok, {child1, child2}} = Exchanger.uniform(parent_a, parent_b, probability: 0.6)
  """
  @spec uniform(SegmentedPrompt.t(), SegmentedPrompt.t(), keyword()) ::
          {:ok, {String.t(), String.t()}} | {:error, term()}
  def uniform(parent_a, parent_b, opts \\ [])

  def uniform(
        %SegmentedPrompt{segments: segs_a} = parent_a,
        %SegmentedPrompt{segments: segs_b} = parent_b,
        opts
      )
      when length(segs_a) > 0 and length(segs_b) > 0 do
    preserve_task = Keyword.get(opts, :preserve_task, true)
    probability = Keyword.get(opts, :probability, 0.5)
    seed = Keyword.get(opts, :seed)

    # Set seed if provided for reproducibility
    if seed, do: :rand.seed(:exsss, {seed, seed, seed})

    with {:ok, {aligned_a, aligned_b}} <- align_segments(segs_a, segs_b, preserve_task) do
      {offspring1_segments, offspring2_segments} =
        Enum.zip(aligned_a, aligned_b)
        |> Enum.map(fn {seg_a, seg_b} ->
          if :rand.uniform() < probability do
            {seg_a, seg_b}
          else
            {seg_b, seg_a}
          end
        end)
        |> Enum.unzip()

      offspring1 = reconstruct_prompt(offspring1_segments, parent_a)
      offspring2 = reconstruct_prompt(offspring2_segments, parent_b)

      {:ok, {offspring1, offspring2}}
    end
  end

  def uniform(_parent_a, _parent_b, _opts) do
    {:error, :invalid_parents}
  end

  # Private functions

  defp align_segments(segs_a, segs_b, preserve_task) do
    # Group segments by type
    by_type_a = Enum.group_by(segs_a, & &1.type)
    by_type_b = Enum.group_by(segs_b, & &1.type)

    # Get all unique types
    all_types = (Map.keys(by_type_a) ++ Map.keys(by_type_b)) |> Enum.uniq()

    # Build aligned segment lists
    {aligned_a, aligned_b} =
      all_types
      |> Enum.reduce({[], []}, fn type, {acc_a, acc_b} ->
        # Handle task description preservation
        if type == :task_description and preserve_task do
          segs_from_a = Map.get(by_type_a, type, [])
          {acc_a ++ segs_from_a, acc_b ++ segs_from_a}
        else
          segs_from_a = Map.get(by_type_a, type, [])
          segs_from_b = Map.get(by_type_b, type, [])

          # Pad to same length
          max_len = max(length(segs_from_a), length(segs_from_b))
          padded_a = pad_segments(segs_from_a, max_len, type)
          padded_b = pad_segments(segs_from_b, max_len, type)

          {acc_a ++ padded_a, acc_b ++ padded_b}
        end
      end)

    if Enum.empty?(aligned_a) or Enum.empty?(aligned_b) do
      {:error, :alignment_failed}
    else
      {:ok, {aligned_a, aligned_b}}
    end
  end

  defp pad_segments(segments, target_length, type) do
    current_length = length(segments)

    if current_length < target_length do
      # Create empty placeholder segments
      padding =
        Enum.map(1..(target_length - current_length), fn _ ->
          %PromptSegment{
            id: Uniq.UUID.uuid4(),
            type: type,
            content: "",
            start_pos: 0,
            end_pos: 0,
            parent_prompt_id: "padding",
            priority: :low,
            metadata: %{placeholder: true}
          }
        end)

      segments ++ padding
    else
      segments
    end
  end

  defp determine_crossover_point(segments, opts) do
    case Keyword.get(opts, :crossover_point) do
      nil ->
        # Random point (avoid 0 and length to ensure actual crossover)
        length = length(segments)

        if length <= 1 do
          1
        else
          :rand.uniform(length - 1)
        end

      point ->
        max(1, min(point, length(segments) - 1))
    end
  end

  defp determine_two_points(segments, opts) do
    case Keyword.get(opts, :points) do
      {p1, p2} when p1 < p2 ->
        {p1, p2}

      _ ->
        # Random two points
        length = length(segments)

        if length <= 2 do
          {1, 1}
        else
          point1 = :rand.uniform(length - 2)
          point2 = point1 + :rand.uniform(length - point1 - 1)
          {point1, point2}
        end
    end
  end

  defp reconstruct_prompt(segments, reference_prompt) do
    # Filter out placeholder segments
    real_segments = Enum.reject(segments, &Map.get(&1.metadata, :placeholder, false))

    # Sort by original position to maintain some structure
    sorted = Enum.sort_by(real_segments, & &1.start_pos)

    # Join segments with appropriate spacing
    sorted
    |> Enum.map(& &1.content)
    |> Enum.reject(&(&1 == ""))
    |> join_with_spacing(reference_prompt.structure_type)
  end

  defp join_with_spacing(segments, structure_type) do
    case structure_type do
      :simple ->
        Enum.join(segments, " ")

      :structured ->
        Enum.join(segments, "\n\n")

      :complex ->
        # Use double newlines for more complex structures
        Enum.join(segments, "\n\n")
    end
  end
end
