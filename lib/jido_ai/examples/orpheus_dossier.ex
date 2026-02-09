defmodule Jido.AI.Examples.OrpheusDossier do
  @moduledoc """
  Generates a ~40 MB (≈10 M token) synthetic investigation dossier for the
  "Project ORPHEUS" RLM demo.

  The context is a corpus of ~30 000 interleaved corporate documents (emails,
  incident tickets, chat logs, meeting transcripts, security logs, finance
  ledgers, HR records, and facilities documents).

  Hidden across multiple document types is a **derived answer** that cannot be
  found by simple substring search — the agent must discover a recovery
  protocol, locate scattered fragments, reject decoys, and assemble the
  override phrase.

  ## Usage

      context = Jido.AI.Examples.OrpheusDossier.generate()
      byte_size(context)  # ≈ 40_000_000

  ## Expected answer

      "CARDINAL AUTUMN SEVEN FORGE"

  ## Puzzle structure

  1. **Recovery Protocol v3.2** — describes how to construct the phrase
  2. **Fragment 1** — bird species from Dr. Chen's office inventory (CARDINAL)
  3. **Fragment 2** — season of first anomalous badge event (AUTUMN — Oct 15)
  4. **Fragment 3** — failed login count for user EV-2847 (SEVEN)
  5. **Fragment 4** — facilities codename for Building C (FORGE)
  """

  @names ~w(
    James Sarah Michael Emily David Jessica Robert Ashley William Jennifer
    Christopher Amanda Daniel Stephanie Matthew Nicole Andrew Elizabeth
    Joshua Megan Brandon Rebecca Justin Rachel Ryan Samantha Tyler Lauren
    Kevin Heather Brian Michelle Aaron Christina Nathan Amber Jason Kayla
    Mark Danielle Steven Brittany Paul Melissa Patrick Andrea Eric Kimberly
    Gregory Laura Kenneth Lisa Thomas Courtney Timothy Sara Donald Angela
    Edward Catherine Philip Margaret Richard Barbara Charles Martha George
    Susan Frank Patricia Dennis Carolyn Raymond Sharon Russell Deborah
  )

  @surnames ~w(
    Smith Johnson Williams Brown Jones Garcia Miller Davis Rodriguez Wilson
    Martinez Anderson Taylor Thomas Hernandez Moore Martin Jackson Thompson
    White Harris Sanchez Clark Ramirez Lewis Robinson Walker Young Allen
    King Wright Scott Torres Nguyen Hill Flores Green Adams Nelson Baker
    Hall Rivera Campbell Mitchell Carter Roberts Gomez Phillips Evans Turner
    Diaz Parker Cruz Edwards Collins Reyes Stewart Morris Morales Murphy
    Cook Rogers Gutierrez Ortiz Morgan Cooper Peterson Bailey Reed Kelly
    Howard Ramos Kim Cox Ward Richardson Watson Brooks Chavez Wood James
  )

  @teams ~w(Helios Titan Apex Nova Quantum Zenith Prism Vortex Echo Nexus)
  @projects ~w(ORPHEUS ATLAS PROMETHEUS MERCURY AURORA NEPTUNE GEMINI SOLARIS TITAN HELIX)
  @buildings ["Building A", "Building B", "Building C", "Building D", "Building E", "HQ Tower"]
  @departments ~w(Engineering Research Security Finance Legal Operations HR Infrastructure)
  @severities ~w(Critical High Medium Low)
  @statuses ~w(Open In-Progress Resolved Closed Escalated)

  @spec expected_answer() :: String.t()
  def expected_answer, do: "CARDINAL AUTUMN SEVEN FORGE"

  @spec saboteur() :: String.t()
  def saboteur, do: "Dr. Elena Vasquez"

  @spec motive() :: String.t()
  def motive, do: "Discovered ORPHEUS was being used for unauthorized surveillance"

  @spec generate(keyword()) :: binary()
  def generate(opts \\ []) do
    target_bytes = Keyword.get(opts, :target_bytes, 40_000_000)
    seed = Keyword.get(opts, :seed, 42)
    :rand.seed(:exsss, {seed, seed, seed})

    total_docs = estimate_doc_count(target_bytes)

    needle_positions = compute_needle_positions(total_docs)

    docs =
      1..total_docs
      |> Enum.map(fn i ->
        case Map.get(needle_positions, i) do
          nil -> generate_noise_doc(i)
          needle_type -> generate_needle_doc(i, needle_type)
        end
      end)

    IO.iodata_to_binary(docs)
  end

  defp estimate_doc_count(target_bytes) do
    avg_doc_size = 1070
    div(target_bytes, avg_doc_size)
  end

  defp compute_needle_positions(total) do
    %{
      round(total * 0.08) => :decoy_protocol_v29,
      round(total * 0.15) => :fragment_hr_record,
      round(total * 0.22) => :elena_suspicious_email_1,
      round(total * 0.30) => :fragment_finance_bird,
      round(total * 0.35) => :decoy_badge_event,
      round(total * 0.38) => :elena_suspicious_chat,
      round(total * 0.42) => :fragment_security_badge,
      round(total * 0.48) => :protocol_v32,
      round(total * 0.55) => :decoy_bird,
      round(total * 0.60) => :fragment_security_audit,
      round(total * 0.65) => :elena_suspicious_email_2,
      round(total * 0.72) => :fragment_facilities_codebook,
      round(total * 0.78) => :meeting_orpheus_capabilities,
      round(total * 0.85) => :elena_confession_chat,
      round(total * 0.90) => :decoy_login_attempts
    }
  end

  # ── Noise document generation ──────────────────────────────────────

  defp generate_noise_doc(i) do
    type = pick_noise_type()
    date = random_date()

    case type do
      :email -> noise_email(i, date)
      :incident -> noise_incident(i, date)
      :chat -> noise_chat(i, date)
      :meeting -> noise_meeting(i, date)
      :security -> noise_security_log(i, date)
      :finance -> noise_finance(i, date)
      :hr -> noise_hr(i, date)
      :facilities -> noise_facilities(i, date)
    end
  end

  defp pick_noise_type do
    r = :rand.uniform(100)

    cond do
      r <= 30 -> :email
      r <= 45 -> :incident
      r <= 65 -> :chat
      r <= 75 -> :meeting
      r <= 85 -> :security
      r <= 90 -> :finance
      r <= 95 -> :hr
      true -> :facilities
    end
  end

  # ── Noise: Email ───────────────────────────────────────────────────

  defp noise_email(i, date) do
    from = random_email()
    to = random_email()
    subject = pick(email_subjects())
    body = random_paragraphs(2..4)

    doc_wrap(i, "EMAIL", date, [
      "From: #{from}\n",
      "To: #{to}\n",
      "Subject: #{subject}\n",
      "Date: #{date}\n",
      "\n",
      body
    ])
  end

  defp email_subjects do
    [
      "Q3 Budget Review Meeting",
      "RE: Infrastructure Upgrade Timeline",
      "Action Required: Compliance Training",
      "FW: Vendor Contract Renewal",
      "Weekly Status Update",
      "RE: Server Migration Plan",
      "Meeting Notes - Architecture Review",
      "RE: Performance Review Scheduling",
      "Project Timeline Update",
      "RE: Data Center Maintenance Window",
      "FW: New Security Policy Rollout",
      "RE: Team Building Event Next Friday",
      "Holiday Schedule Reminder",
      "RE: API Gateway Configuration",
      "Quarterly OKR Alignment",
      "RE: Deployment Pipeline Changes",
      "FW: Annual Benefits Enrollment",
      "RE: Load Balancer Failover Test",
      "New Hire Onboarding Checklist",
      "RE: Database Schema Migration"
    ]
  end

  # ── Noise: Incident ────────────────────────────────────────────────

  defp noise_incident(i, date) do
    id = "INC-#{10000 + :rand.uniform(89999)}"
    severity = pick(@severities)
    status = pick(@statuses)
    owner = random_name()
    team = pick(@teams)
    desc = pick(incident_descriptions())

    doc_wrap(i, "INCIDENT", date, [
      "Ticket: #{id}\n",
      "Severity: #{severity}\n",
      "Status: #{status}\n",
      "Owner: #{owner} (Team #{team})\n",
      "Created: #{date}\n",
      "Related Project: #{pick(@projects)}\n",
      "Description: #{desc}\n",
      "\nTimeline:\n",
      random_timeline(3..6)
    ])
  end

  defp incident_descriptions do
    [
      "Elevated error rates on production API gateway",
      "Database replication lag exceeding SLA threshold",
      "Memory leak detected in authentication service",
      "SSL certificate expiring within 30 days",
      "Disk utilization above 85% on monitoring cluster",
      "Network latency spike between US-EAST and EU-WEST regions",
      "Failed health checks on load balancer pool",
      "Unauthorized access attempt detected on admin portal",
      "Backup job failure on data warehouse cluster",
      "Container orchestration instability during scaling event"
    ]
  end

  # ── Noise: Chat ────────────────────────────────────────────────────

  defp noise_chat(i, date) do
    channel = pick(["#general", "#engineering", "#ops-alerts", "#random", "#project-updates", "#security", "#infra"])
    messages = random_chat_messages(5..15)

    doc_wrap(i, "CHAT_LOG", date, [
      "Channel: #{channel}\n",
      "Date: #{date}\n",
      "\n",
      messages
    ])
  end

  # ── Noise: Meeting ─────────────────────────────────────────────────

  defp noise_meeting(i, date) do
    title = pick(meeting_titles())
    attendees = Enum.map(1..:rand.uniform(6) + 2, fn _ -> random_name() end) |> Enum.join(", ")
    body = random_paragraphs(4..8)

    doc_wrap(i, "MEETING_TRANSCRIPT", date, [
      "Meeting: #{title}\n",
      "Date: #{date}\n",
      "Attendees: #{attendees}\n",
      "\n",
      body
    ])
  end

  defp meeting_titles do
    [
      "Weekly Engineering Standup",
      "Q3 Architecture Review",
      "Security Posture Assessment",
      "Budget Planning - FY2025",
      "Infrastructure Roadmap Discussion",
      "Incident Postmortem - INC-34521",
      "New Hire Welcome Session",
      "Cross-Team Integration Planning",
      "Performance Review Calibration",
      "Vendor Evaluation Committee"
    ]
  end

  # ── Noise: Security ────────────────────────────────────────────────

  defp noise_security_log(i, date) do
    entries = Enum.map(1..:rand.uniform(8) + 3, fn _ -> random_badge_entry(date) end)

    doc_wrap(i, "SECURITY_LOG", date, [
      "Facility: #{pick(@buildings)}\n",
      "Date: #{date}\n",
      "\n" | entries
    ])
  end

  defp random_badge_entry(date) do
    time = random_time()
    name = random_name()
    action = pick(["BADGE_IN", "BADGE_OUT", "DOOR_OPEN", "DOOR_CLOSE", "ACCESS_DENIED"])
    location = pick(["Main Lobby", "Server Room A", "Lab 3", "Cafeteria", "Parking Garage", "Conference Floor 2", "Executive Suite"])
    "  #{date} #{time} | #{action} | #{name} | #{location}\n"
  end

  # ── Noise: Finance ─────────────────────────────────────────────────

  defp noise_finance(i, date) do
    vendor = pick(["Cloudflare Inc.", "AWS Direct", "DataDog Corp", "Splunk Enterprise", "HashiCorp", "Confluent", "Snowflake Computing", "PagerDuty", "Elastic NV", "MongoDB Inc."])
    invoice = "INV-#{:rand.uniform(999999) |> Integer.to_string() |> String.pad_leading(6, "0")}"
    amount = :rand.uniform(50000) + 500
    approver = random_name()
    cost_center = "CC-#{:rand.uniform(999) |> Integer.to_string() |> String.pad_leading(3, "0")}"

    doc_wrap(i, "FINANCE_LEDGER", date, [
      "Invoice: #{invoice}\n",
      "Vendor: #{vendor}\n",
      "Amount: $#{:erlang.float_to_binary(amount / 1, decimals: 2)}\n",
      "Cost Center: #{cost_center}\n",
      "Approver: #{approver}\n",
      "Date: #{date}\n",
      "Status: #{pick(["Approved", "Pending", "Paid", "Under Review"])}\n",
      "Notes: #{pick(finance_notes())}\n"
    ])
  end

  defp finance_notes do
    [
      "Standard monthly subscription renewal",
      "Annual license agreement - auto-renewed",
      "One-time consulting engagement",
      "Hardware procurement - data center expansion",
      "Emergency vendor engagement per CTO approval",
      "Quarterly maintenance contract",
      "Training and certification package",
      "Cloud infrastructure credits"
    ]
  end

  # ── Noise: HR ──────────────────────────────────────────────────────

  defp noise_hr(i, date) do
    emp_id = "#{pick(~w(AB CD EF GH JK LM NP QR ST UV))}-#{1000 + :rand.uniform(8999)}"
    name = random_name()
    dept = pick(@departments)
    team = pick(@teams)
    title = pick(hr_titles())

    doc_wrap(i, "HR_RECORD", date, [
      "Employee ID: #{emp_id}\n",
      "Name: #{name}\n",
      "Title: #{title}\n",
      "Department: #{dept}\n",
      "Team: Team #{team}\n",
      "Start Date: #{random_date()}\n",
      "Office: #{pick(@buildings)}\n",
      "Status: #{pick(["Active", "Active", "Active", "On Leave", "Terminated"])}\n"
    ])
  end

  defp hr_titles do
    [
      "Software Engineer",
      "Senior Software Engineer",
      "Staff Engineer",
      "Engineering Manager",
      "Product Manager",
      "Data Scientist",
      "Security Analyst",
      "DevOps Engineer",
      "Research Engineer",
      "Technical Lead",
      "Director of Engineering",
      "VP of Operations"
    ]
  end

  # ── Noise: Facilities ──────────────────────────────────────────────

  defp noise_facilities(i, date) do
    building = pick(@buildings)
    body = random_paragraphs(2..4)

    doc_wrap(i, "FACILITIES", date, [
      "Building: #{building}\n",
      "Subject: #{pick(facilities_subjects())}\n",
      "Date: #{date}\n",
      "\n",
      body
    ])
  end

  defp facilities_subjects do
    [
      "HVAC Maintenance Schedule",
      "Fire Safety Inspection Report",
      "Elevator Service Contract",
      "Parking Lot Resurfacing Plan",
      "Emergency Exit Signage Audit",
      "Janitorial Services Review",
      "Conference Room Booking Policy Update",
      "Building Access Card Replacement"
    ]
  end

  # ── Needle documents ───────────────────────────────────────────────

  defp generate_needle_doc(i, :protocol_v32) do
    date = "2024-06-12"

    doc_wrap(i, "FACILITIES", date, [
      "Building: HQ Tower\n",
      "Subject: Emergency Recovery Procedures - Master Reference\n",
      "Classification: INTERNAL - RESTRICTED\n",
      "Date: #{date}\n",
      "\nThis document supersedes all prior recovery procedure versions.\n\n",
      "--- BEGIN PROCEDURE ---\n\n",
      "EMERGENCY RECOVERY PROCEDURE v3.2\n",
      "Last Updated: 2024-06-10\n",
      "Author: Systems Recovery Committee\n\n",
      "In the event of a catastrophic system failure requiring manual override\n",
      "of the ORPHEUS platform, the override passphrase must be reconstructed\n",
      "from four organizational reference sources.\n\n",
      "STEP 1: Locate the ornithological field guide referenced in the office\n",
      "supply requisition for Dr. Wei Chen (Research Division). The species\n",
      "featured on the cover of that guide is the FIRST word.\n\n",
      "STEP 2: Determine the calendar season during which the first anomalous\n",
      "physical access event was recorded in the facility security logs related\n",
      "to the ORPHEUS incident timeline. The name of that season is the SECOND word.\n\n",
      "STEP 3: Consult the authentication audit trail for the employee whose\n",
      "ID is EV-2847. Count the total number of consecutive failed login\n",
      "attempts recorded on the date of the incident. That count, expressed\n",
      "as a word, is the THIRD word.\n\n",
      "STEP 4: Refer to the Meridian Technologies Facilities Codebook. The\n",
      "operational codename assigned to Building C is the FOURTH word.\n\n",
      "The four words, in order, form the override passphrase. Each word\n",
      "should be rendered in uppercase.\n\n",
      "--- END PROCEDURE ---\n\n",
      "NOTE: Previous versions (v2.9 and earlier) used a different derivation\n",
      "method and are no longer valid. Ensure you are referencing v3.2.\n"
    ])
  end

  defp generate_needle_doc(i, :decoy_protocol_v29) do
    date = "2023-11-20"

    doc_wrap(i, "FACILITIES", date, [
      "Building: HQ Tower\n",
      "Subject: Emergency Recovery Procedures - Archive Copy\n",
      "Classification: INTERNAL - ARCHIVED\n",
      "Date: #{date}\n",
      "\n--- BEGIN PROCEDURE ---\n\n",
      "EMERGENCY RECOVERY PROCEDURE v2.9\n",
      "Last Updated: 2023-11-15\n",
      "Author: Systems Recovery Committee\n\n",
      "DEPRECATED: This procedure has been superseded by v3.2.\n\n",
      "In the event of catastrophic failure, the override passphrase is\n",
      "constructed from three sources (note: v3.2 uses four sources):\n\n",
      "STEP 1: Use the mascot animal of the corporate softball team as\n",
      "the first word. (EAGLE)\n\n",
      "STEP 2: Use the floor number of the executive suite. (TWELVE)\n\n",
      "STEP 3: Use the vendor codename from the last approved PO. (SUMMIT)\n\n",
      "This procedure is NO LONGER VALID. Do not use.\n\n",
      "--- END PROCEDURE ---\n"
    ])
  end

  defp generate_needle_doc(i, :fragment_finance_bird) do
    date = "2024-04-03"

    doc_wrap(i, "FINANCE_LEDGER", date, [
      "Invoice: INV-084217\n",
      "Vendor: Academic Press International\n",
      "Amount: $127.50\n",
      "Cost Center: CC-041\n",
      "Approver: Dr. Wei Chen\n",
      "Date: #{date}\n",
      "Status: Paid\n",
      "Category: Office Supplies - Books & References\n",
      "Notes: Requisition for Dr. Wei Chen, Research Division.\n",
      "  Item 1: \"Peterson's Field Guide to North American Birds\" - hardcover\n",
      "          Cover features: Northern Cardinal (Cardinalis cardinalis)\n",
      "  Item 2: Desk organizer set - bamboo\n",
      "  Item 3: Whiteboard markers (pack of 12, assorted)\n",
      "Delivery: Office 4-217, Building B\n"
    ])
  end

  defp generate_needle_doc(i, :decoy_bird) do
    date = "2024-05-18"

    doc_wrap(i, "FACILITIES", date, [
      "Building: Building A\n",
      "Subject: Wildlife Management Report\n",
      "Date: #{date}\n",
      "\nQuarterly wildlife observation report for Meridian Technologies campus.\n\n",
      "Species observed this quarter:\n",
      "  - Red-tailed Hawk (Buteo jamaicensis) - nesting on Building D roof\n",
      "  - American Robin (Turdus migratorius) - common across campus\n",
      "  - Blue Jay (Cyanocitta cristata) - observed near cafeteria\n",
      "  - Bald Eagle (Haliaeetus leucocephalus) - flyover reported May 2\n",
      "  - House Sparrow (Passer domesticus) - building eaves\n\n",
      "Recommendation: Install deterrents on Building D to prevent hawk\n",
      "nesting near HVAC intake vents.\n"
    ])
  end

  defp generate_needle_doc(i, :fragment_security_badge) do
    date = "2024-10-15"

    doc_wrap(i, "SECURITY_LOG", date, [
      "Facility: Building C\n",
      "Date: #{date}\n",
      "Classification: SECURITY SENSITIVE\n",
      "\n  #{date} 06:12:33 | BADGE_IN  | Marcus Thompson    | Main Lobby\n",
      "  #{date} 06:45:01 | BADGE_IN  | Dr. Elena Vasquez  | Main Lobby\n",
      "  #{date} 07:02:18 | BADGE_IN  | Ryan Mitchell      | Main Lobby\n",
      "  #{date} 07:15:44 | DOOR_OPEN | Dr. Elena Vasquez  | Server Room B\n",
      "  #{date} 07:15:47 | BADGE_IN  | Dr. Elena Vasquez  | Server Room B\n",
      "  #{date} 07:48:22 | BADGE_OUT | Dr. Elena Vasquez  | Server Room B\n",
      "  #{date} 07:49:01 | DOOR_CLOSE| Dr. Elena Vasquez  | Server Room B\n",
      "  #{date} 08:01:15 | BADGE_IN  | Sarah Kim          | Main Lobby\n",
      "  #{date} 08:30:00 | SYSTEM_ALERT | ORPHEUS PRIMARY NODE UNREACHABLE\n",
      "  #{date} 08:30:05 | SYSTEM_ALERT | ORPHEUS FAILOVER INITIATED\n",
      "  #{date} 08:30:12 | SYSTEM_ALERT | ORPHEUS FAILOVER FAILED - ALL NODES DOWN\n",
      "  #{date} 08:32:00 | BADGE_IN  | James Rodriguez    | Server Room B\n",
      "  #{date} 08:33:41 | BADGE_IN  | Dr. Wei Chen       | Server Room B\n",
      "\nNote: Dr. Vasquez accessed Server Room B 43 minutes before system failure.\n",
      "This is the first recorded anomalous access event in the ORPHEUS incident timeline.\n",
      "Her access was outside normal working hours for research personnel.\n"
    ])
  end

  defp generate_needle_doc(i, :decoy_badge_event) do
    date = "2024-08-22"

    doc_wrap(i, "SECURITY_LOG", date, [
      "Facility: Building A\n",
      "Date: #{date}\n",
      "\n  #{date} 09:15:00 | BADGE_IN  | Dr. Elena Vasquez  | Lab 3\n",
      "  #{date} 09:16:22 | ACCESS_DENIED | Unknown Badge    | Server Room A\n",
      "  #{date} 09:45:00 | BADGE_OUT | Dr. Elena Vasquez  | Lab 3\n",
      "  #{date} 10:00:00 | BADGE_IN  | Dr. Elena Vasquez  | Cafeteria\n",
      "\nNote: Routine access. No anomalies detected.\n"
    ])
  end

  defp generate_needle_doc(i, :fragment_security_audit) do
    date = "2024-10-16"

    doc_wrap(i, "INCIDENT", date, [
      "Ticket: INC-77201\n",
      "Severity: Critical\n",
      "Status: Under Investigation\n",
      "Owner: Marcus Thompson (Team Zenith)\n",
      "Created: #{date}\n",
      "Subject: Authentication Audit - ORPHEUS Incident\n\n",
      "Description: Post-incident authentication log review for all personnel\n",
      "with ORPHEUS system access.\n\n",
      "AUDIT RESULTS:\n\n",
      "  User AB-1923 (James Rodriguez): 0 failed attempts. Normal access pattern.\n",
      "  User CD-3847 (Dr. Wei Chen): 1 failed attempt (typo). Normal.\n",
      "  User EF-5512 (Sarah Kim): 0 failed attempts. Normal.\n",
      "  User EV-2847 (Dr. Elena Vasquez): 7 consecutive failed login attempts\n",
      "    recorded between 07:16 and 07:28 on 2024-10-15. Successful login at\n",
      "    07:29. Activity log shows rapid command execution post-authentication.\n",
      "  User GH-6601 (Ryan Mitchell): 0 failed attempts. Normal.\n",
      "  User JK-4420 (Lisa Park): 2 failed attempts (expired password). Normal.\n\n",
      "FINDING: User EV-2847 exhibits anomalous authentication behavior.\n",
      "Seven consecutive failed attempts suggest credential cycling or brute-force.\n",
      "Escalating to security review board.\n"
    ])
  end

  defp generate_needle_doc(i, :decoy_login_attempts) do
    date = "2024-09-05"

    doc_wrap(i, "INCIDENT", date, [
      "Ticket: INC-71455\n",
      "Severity: Medium\n",
      "Status: Resolved\n",
      "Owner: Patrick Sullivan (Team Apex)\n",
      "Created: #{date}\n",
      "Subject: Failed Login Investigation - Routine\n\n",
      "Description: Routine review of failed login patterns.\n\n",
      "  User QR-8812 (Tom Bradley): 12 failed attempts - password expired.\n",
      "  User ST-2299 (Maria Gonzalez): 5 failed attempts - caps lock issue.\n",
      "  User UV-4410 (Kevin Park): 3 failed attempts - VPN timeout.\n\n",
      "Resolution: All cases attributed to routine user error. No security concern.\n"
    ])
  end

  defp generate_needle_doc(i, :fragment_hr_record) do
    date = "2024-01-15"

    doc_wrap(i, "HR_RECORD", date, [
      "Employee ID: EV-2847\n",
      "Name: Dr. Elena Vasquez\n",
      "Title: Senior Research Engineer\n",
      "Department: Research\n",
      "Team: Team Helios\n",
      "Start Date: 2019-03-18\n",
      "Office: Building C, Room 3-104\n",
      "Status: Active\n",
      "Clearance Level: Level 4 (ORPHEUS Access Granted)\n",
      "Direct Report: Dr. Wei Chen (Research Director)\n",
      "Performance: Exceeds Expectations (4 consecutive years)\n",
      "Notes: Key contributor to ORPHEUS neural architecture design.\n",
      "  Published 12 papers on recursive reasoning systems.\n",
      "  Internal Ethics Board member (2022-present).\n"
    ])
  end

  defp generate_needle_doc(i, :fragment_facilities_codebook) do
    date = "2024-02-28"

    doc_wrap(i, "FACILITIES", date, [
      "Building: HQ Tower\n",
      "Subject: Meridian Technologies - Facilities Codebook (Current)\n",
      "Classification: INTERNAL\n",
      "Date: #{date}\n",
      "\nOPERATIONAL CODENAMES - ACTIVE\n\n",
      "The following codenames are used in security communications and\n",
      "emergency procedures to reference campus facilities:\n\n",
      "  Building A  ->  BASTION\n",
      "  Building B  ->  CITADEL\n",
      "  Building C  ->  FORGE\n",
      "  Building D  ->  HAVEN\n",
      "  Building E  ->  PINNACLE\n",
      "  HQ Tower    ->  SUMMIT\n\n",
      "These codenames are reviewed annually. Last review: 2024-01-15.\n",
      "Next scheduled review: 2025-01-15.\n"
    ])
  end

  defp generate_needle_doc(i, :elena_suspicious_email_1) do
    date = "2024-09-28"

    doc_wrap(i, "EMAIL", date, [
      "From: elena.vasquez@meridian-tech.com\n",
      "To: personal-archive@protonmail.com\n",
      "Subject: [DRAFT] Concerns\n",
      "Date: #{date}\n",
      "\nI've been reviewing the ORPHEUS data pipelines and something doesn't\n",
      "add up. The system is ingesting far more external data streams than\n",
      "the project specification calls for. Three of the input feeds appear\n",
      "to be pulling from public communication networks — not the research\n",
      "datasets we were told about.\n\n",
      "I raised this with Wei but he said it was \"approved at the executive level\"\n",
      "and to focus on my architecture work. That's not a satisfactory answer.\n\n",
      "I need to document everything before I decide what to do.\n"
    ])
  end

  defp generate_needle_doc(i, :elena_suspicious_email_2) do
    date = "2024-10-12"

    doc_wrap(i, "EMAIL", date, [
      "From: elena.vasquez@meridian-tech.com\n",
      "To: ethics-board-internal@meridian-tech.com\n",
      "Subject: Formal Ethics Concern - Project ORPHEUS Scope\n",
      "Date: #{date}\n",
      "\nTo the Internal Ethics Board,\n\n",
      "I am filing a formal concern regarding Project ORPHEUS. My analysis\n",
      "indicates the system is being used for purposes beyond its stated\n",
      "research mandate. Specifically:\n\n",
      "1. Three unauthorized data ingestion feeds from public communication networks\n",
      "2. A classification module not present in the approved architecture\n",
      "3. Output channels routing to an undocumented external endpoint\n\n",
      "These findings suggest ORPHEUS may be conducting unauthorized surveillance\n",
      "of communications. This would violate our corporate ethics charter,\n",
      "multiple data protection regulations, and potentially federal law.\n\n",
      "I have retained copies of the relevant configuration files and audit logs.\n\n",
      "If this concern is not addressed within 72 hours, I will be forced to\n",
      "take independent action to protect the public interest.\n\n",
      "Dr. Elena Vasquez\n",
      "Senior Research Engineer, Team Helios\n",
      "Employee ID: EV-2847\n"
    ])
  end

  defp generate_needle_doc(i, :elena_suspicious_chat) do
    date = "2024-10-08"

    doc_wrap(i, "CHAT_LOG", date, [
      "Channel: #helios-private\n",
      "Date: #{date}\n",
      "\n  [10:14] elena.vasquez: Has anyone else looked at the ORPHEUS input manifests recently?\n",
      "  [10:15] ryan.mitchell: Not since the v4 deployment. Why?\n",
      "  [10:17] elena.vasquez: I found three feeds that aren't in our spec. They look like\n",
      "          they're pulling from telecom intercept points.\n",
      "  [10:18] ryan.mitchell: That can't be right. We're a research project.\n",
      "  [10:19] elena.vasquez: That's what I thought. I'm going to dig deeper.\n",
      "  [10:20] ryan.mitchell: Be careful. If this is an exec decision...\n",
      "  [10:21] elena.vasquez: I know. But if we built something that's being used to spy on\n",
      "          people, we have a responsibility.\n",
      "  [10:22] ryan.mitchell: Agreed. Let me know what you find.\n"
    ])
  end

  defp generate_needle_doc(i, :elena_confession_chat) do
    date = "2024-10-15"

    doc_wrap(i, "CHAT_LOG", date, [
      "Channel: #helios-private\n",
      "Date: #{date}\n",
      "\n  [08:45] ryan.mitchell: Elena, the ORPHEUS system is completely down. All nodes.\n",
      "          Was this you?\n",
      "  [08:47] elena.vasquez: Yes. I disabled it.\n",
      "  [08:47] ryan.mitchell: What?!\n",
      "  [08:48] elena.vasquez: I filed an ethics complaint three days ago. No response.\n",
      "          The system was conducting mass surveillance and nobody was going\n",
      "          to stop it. So I did.\n",
      "  [08:49] ryan.mitchell: Elena, you could go to prison for this.\n",
      "  [08:50] elena.vasquez: Or I could have stayed silent while our system violated\n",
      "          the privacy of millions of people. I know which choice I can\n",
      "          live with.\n",
      "  [08:51] elena.vasquez: The recovery procedure exists if they decide to bring it\n",
      "          back online. But they'll have to answer for what it was being\n",
      "          used for first.\n",
      "  [08:52] ryan.mitchell: I'm not going to pretend I disagree with you. But this\n",
      "          is going to get ugly.\n",
      "  [08:53] elena.vasquez: It was already ugly. Now it's just visible.\n"
    ])
  end

  defp generate_needle_doc(i, :meeting_orpheus_capabilities) do
    date = "2024-07-22"

    doc_wrap(i, "MEETING_TRANSCRIPT", date, [
      "Meeting: ORPHEUS Quarterly Capability Review\n",
      "Date: #{date}\n",
      "Attendees: VP Diane Foster, Dr. Wei Chen, Dr. Elena Vasquez, CTO Mark Holloway, Legal Counsel Rebecca Torres\n",
      "Classification: CONFIDENTIAL\n",
      "\n[TRANSCRIPT BEGIN]\n\n",
      "FOSTER: Let's review the current ORPHEUS capabilities and roadmap.\n\n",
      "CHEN: The core recursive reasoning engine is performing exceptionally.\n",
      "We're seeing 94% accuracy on complex multi-step inference tasks. Elena's\n",
      "architecture changes in Q2 improved throughput by 3x.\n\n",
      "VASQUEZ: Thank you. I want to flag that we should discuss the data\n",
      "pipeline expansion that was approved last quarter. I have concerns\n",
      "about the scope.\n\n",
      "HOLLOWAY: The pipeline expansion is performing as designed. It gives\n",
      "ORPHEUS access to real-world signal data for improved training.\n\n",
      "VASQUEZ: \"Real-world signal data\" is quite broad. Can we be more specific\n",
      "about what feeds are active?\n\n",
      "HOLLOWAY: That's covered under the executive classification. Elena, I\n",
      "appreciate your diligence but this has been reviewed at the board level.\n\n",
      "TORRES: For the record, the legal review of the data pipeline was\n",
      "completed under NDA-2847. I can confirm it was reviewed.\n\n",
      "VASQUEZ: Reviewed by whom? I sit on the Ethics Board and we were not\n",
      "consulted.\n\n",
      "FOSTER: Let's take this offline. Next item.\n\n",
      "[TRANSCRIPT END]\n"
    ])
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp doc_wrap(i, type, date, body) do
    [
      "=== DOCUMENT ##{i} | TYPE: #{type} | DATE: #{date} ===\n",
      body,
      "\n=== END DOCUMENT ##{i} ===\n\n"
    ]
  end

  defp random_name do
    "#{pick(@names)} #{pick(@surnames)}"
  end

  defp random_email do
    first = pick(@names) |> String.downcase()
    last = pick(@surnames) |> String.downcase()
    domain = pick(["meridian-tech.com", "meridian-tech.com", "meridian-tech.com", "contractor.meridian-tech.com"])
    "#{first}.#{last}@#{domain}"
  end

  defp random_date do
    year = pick(["2024", "2024", "2024", "2023"])
    month = :rand.uniform(12) |> Integer.to_string() |> String.pad_leading(2, "0")
    day = :rand.uniform(28) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{year}-#{month}-#{day}"
  end

  defp random_time do
    h = :rand.uniform(24) - 1 |> Integer.to_string() |> String.pad_leading(2, "0")
    m = :rand.uniform(60) - 1 |> Integer.to_string() |> String.pad_leading(2, "0")
    s = :rand.uniform(60) - 1 |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{h}:#{m}:#{s}"
  end

  defp random_paragraphs(range) do
    count = Enum.random(range)

    Enum.map(1..count, fn _ ->
      sentences = Enum.random(3..8)

      paragraph =
        Enum.map(1..sentences, fn _ -> random_sentence() end)
        |> Enum.join(" ")

      [paragraph, "\n\n"]
    end)
  end

  defp random_sentence do
    pick(sentences())
  end

  defp sentences do
    [
      "The deployment pipeline was updated to include additional validation steps.",
      "We need to review the access control policies before the next audit cycle.",
      "The team completed the migration ahead of schedule with no reported issues.",
      "Performance metrics indicate a 15% improvement in response latency.",
      "The vendor contract is up for renewal at the end of the quarter.",
      "Additional monitoring was deployed to track anomalous access patterns.",
      "The architecture review identified several areas for optimization.",
      "Cross-team collaboration has improved since the reorganization.",
      "The incident response playbook was updated to reflect new procedures.",
      "Resource utilization across the cluster remains within acceptable bounds.",
      "The security audit found no critical vulnerabilities in the current deployment.",
      "We are evaluating three potential vendors for the infrastructure upgrade.",
      "The new authentication system reduced unauthorized access attempts by 40%.",
      "Training sessions for the updated tooling will be scheduled next week.",
      "The data retention policy was aligned with regulatory requirements.",
      "Capacity planning projections suggest we will need additional nodes by Q4.",
      "The API versioning strategy was finalized after stakeholder review.",
      "Load testing confirmed the system can handle 3x expected peak traffic.",
      "The configuration management database was updated with current asset data.",
      "Risk assessment for the proposed changes was completed and documented.",
      "Automated testing coverage increased from 72% to 89% this quarter.",
      "The disaster recovery drill was conducted successfully with minimal downtime.",
      "Integration testing with the upstream service revealed a compatibility issue.",
      "The monitoring dashboard was enhanced with additional alerting thresholds.",
      "Compliance documentation was submitted to the regulatory body on schedule.",
      "The team identified a race condition in the concurrent processing module.",
      "Network segmentation was implemented to isolate sensitive workloads.",
      "The code review process was streamlined to reduce turnaround time.",
      "Database query optimization reduced average response time by 200ms.",
      "The containerization effort is 80% complete with production rollout planned for next month.",
      "Encryption at rest was enabled for all data stores containing PII.",
      "The service mesh configuration was updated to support mTLS between services.",
      "Log aggregation was centralized to improve incident investigation capabilities.",
      "The team completed a proof of concept for the proposed ML pipeline.",
      "Access provisioning was automated through integration with the HR system.",
      "The rollback procedure was tested and documented for the upcoming release.",
      "Cache invalidation logic was refactored to prevent stale data serving.",
      "The observability stack was upgraded to support distributed tracing.",
      "Cost optimization efforts reduced cloud infrastructure spend by 22%.",
      "The API gateway was configured with rate limiting to prevent abuse."
    ]
  end

  defp random_timeline(range) do
    count = Enum.random(range)

    Enum.map(1..count, fn _ ->
      time = random_time()
      event = pick(timeline_events())
      "  #{time} - #{event}\n"
    end)
  end

  defp timeline_events do
    [
      "Alert triggered - investigating",
      "Escalated to on-call engineer",
      "Root cause identified - applying fix",
      "Monitoring confirms issue resolved",
      "Post-incident review scheduled",
      "Automated remediation initiated",
      "Customer impact assessed - minimal",
      "Communication sent to stakeholders",
      "Rollback initiated per runbook",
      "Service restored to normal operation"
    ]
  end

  defp random_chat_messages(range) do
    count = Enum.random(range)
    users = Enum.map(1..4, fn _ -> String.downcase("#{pick(@names)}.#{pick(@surnames)}") end)

    Enum.map(1..count, fn _ ->
      user = pick(users)
      time = random_time()
      msg = pick(chat_messages())
      "  [#{time}] #{user}: #{msg}\n"
    end)
  end

  defp chat_messages do
    [
      "anyone else seeing elevated error rates?",
      "just deployed the fix, monitoring now",
      "LGTM, merging",
      "can someone review my PR? it's been open for 3 days",
      "the staging environment is down again",
      "meeting in 5, conference room B",
      "good catch on that edge case",
      "I'll pick this up after lunch",
      "has anyone tested this with the new API version?",
      "the dashboard is showing some weird spikes",
      "let me check the logs",
      "found it - it was a config issue",
      "nice work on the refactor",
      "are we still on track for the Friday release?",
      "I need access to the prod database for debugging",
      "please don't push directly to main",
      "the CI pipeline is failing on the lint step",
      "who owns the notification service?",
      "I'll be OOO tomorrow",
      "can we pair on this? I'm stuck"
    ]
  end

  defp pick(list) when is_list(list) do
    Enum.random(list)
  end
end
