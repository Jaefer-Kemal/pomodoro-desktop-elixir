alias PomodoroApp.Repo
alias PomodoroApp.Schedule.{StudyBlock, WeeklyReview}

# Clear existing seeded blocks if needed
Repo.delete_all(StudyBlock)
Repo.delete_all(WeeklyReview)

# ── Seed 8 Weekly Reviews (Starting October 14, 2026) ──
reviews = [
  %{
    week_number: 1,
    week_label: "Week 1 (Oct 14 – Oct 20) · Recursion & Elixir OTP",
    deliverable_notes: "Small supervised application that crashes and restarts cleanly"
  },
  %{
    week_number: 2,
    week_label: "Week 2 (Oct 21 – Oct 27) · Recursion Mastery & C# OOP",
    deliverable_notes: "Recursive call tracing error log + core C# OOP class hierarchy"
  },
  %{
    week_number: 3,
    week_label: "Week 3 (Oct 28 – Nov 03) · Graphs BFS/DFS & Learn You Some Erlang",
    deliverable_notes: "Binary-parsing exercise in Erlang (syntax, patterns, bit syntax)"
  },
  %{
    week_number: 4,
    week_label: "Week 4 (Nov 04 – Nov 10) · Cycle Detection & Erlang ETS",
    deliverable_notes: "ETS-backed lookup example & C# LINQ collection comparisons"
  },
  %{
    week_number: 5,
    week_label: "Week 5 (Nov 11 – Nov 17) · DP From First Principles & Adopting Erlang",
    deliverable_notes: "rebar3 scaffold for etchat_core application structure"
  },
  %{
    week_number: 6,
    week_label: "Week 6 (Nov 18 – Nov 24) · 2D DP Recurrence & Erlang Releases",
    deliverable_notes: "etchat_core builds and runs reproducibly with release inspection"
  },
  %{
    week_number: 7,
    week_label: "Week 7 (Nov 25 – Dec 01) · Mixed DP Practice & Scalability/Debugging",
    deliverable_notes: "Operational debugging checklist & MongooseIM concept map (no prod testing)"
  },
  %{
    week_number: 8,
    week_label: "Week 8 (Dec 02 – Dec 08) · Mixed Retention & C# Console App",
    deliverable_notes: "Standalone C# console app built from scratch demonstrating fundamentals"
  }
]

for r <- reviews do
  Repo.insert!(%WeeklyReview{
    week_number: r.week_number,
    week_label: r.week_label,
    deliverable_notes: r.deliverable_notes,
    concept_explained: false,
    problems_solved: false,
    erlang_code_run: false,
    csharp_progress: false,
    book_ideas_captured: false,
    next_monday_task_selected: false,
    completed: false
  })
end

# ── Seed Daily Study Blocks (Mon=1 through Sat=6, Sun=7) ──
# Monday to Saturday common morning blocks:
study_days = 1..6

for day <- study_days do
  # 8:00 - 10:00: CodeIntuition
  Repo.insert!(%StudyBlock{
    day_of_week: day,
    start_time: ~T[08:00:00],
    end_time: ~T[10:00:00],
    subject: "CodeIntuition",
    title: "CodeIntuition — Problem Solving",
    color: "#6366f1",
    icon: "brain",
    description: "10m recall yesterday, 35m study concepts, 60m solve/implement, 15m error log & Anki",
    is_rest_block: false
  })

  # 10:00 - 10:15: Break
  Repo.insert!(%StudyBlock{
    day_of_week: day,
    start_time: ~T[10:00:00],
    end_time: ~T[10:15:00],
    subject: "Break",
    title: "Morning Refresh Break",
    color: "#10b981",
    icon: "coffee",
    description: "Get away from the screen, walk around, and rest before Erlang",
    is_rest_block: true
  })

  # 10:15 - 11:15: Erlang/Elixir
  Repo.insert!(%StudyBlock{
    day_of_week: day,
    start_time: ~T[10:15:00],
    end_time: ~T[11:15:00],
    subject: "Erlang/Elixir",
    title: "Erlang/Elixir — Job Prep",
    color: "#f43f5e",
    icon: "flame",
    description: "30m reading/concept review + 30m coding, tracing, and OTP experimentation",
    is_rest_block: false
  })

  # 11:15 - 12:00: Rotating Block depending on day
  rotating_block =
    case day do
      1 ->
        %{
          subject: "C# / .NET",
          title: "C# Course — New Concepts",
          color: "#8b5cf6",
          icon: "code",
          description: "Types, methods, OOP, classes, properties, constructors"
        }

      2 ->
        %{
          subject: "Erlang/Elixir",
          title: "Erlang Practical Work",
          color: "#f43f5e",
          icon: "terminal",
          description: "Code from current book, supervisors, and process lifecycles"
        }

      3 ->
        %{
          subject: "C# / .NET",
          title: "C# Course — Code Along",
          color: "#8b5cf6",
          icon: "code",
          description: "Continue course lessons, type examples, practice syntax"
        }

      4 ->
        %{
          subject: "Engineering Book",
          title: "Software Engineering Book",
          color: "#06b6d4",
          icon: "book",
          description: "Design principles, architecture, APIs, or systems engineering"
        }

      5 ->
        %{
          subject: "C# / .NET",
          title: "C# Course — Implementation",
          color: "#8b5cf6",
          icon: "code",
          description: "Exercises, recap, or small implementation"
        }

      6 ->
        %{
          subject: "Weekly Review",
          title: "Weekly Review & Deliverable",
          color: "#eab308",
          icon: "check-circle",
          description: "Complete 6-point checklist and alternate between Erlang and C# deliverable"
        }
    end

  Repo.insert!(%StudyBlock{
    day_of_week: day,
    start_time: ~T[11:15:00],
    end_time: ~T[12:00:00],
    subject: rotating_block.subject,
    title: rotating_block.title,
    color: rotating_block.color,
    icon: rotating_block.icon,
    description: rotating_block.description,
    is_rest_block: false
  })

  # 12:00 - 14:00: Lunch, Prayer, Rest
  Repo.insert!(%StudyBlock{
    day_of_week: day,
    start_time: ~T[12:00:00],
    end_time: ~T[14:00:00],
    subject: "Lunch & Prayer",
    title: "Lunch, Prayer & Rest",
    color: "#64748b",
    icon: "sun",
    description: "No extra studying squeezed in. Recharge for afternoon.",
    is_rest_block: true
  })

  # 14:00 - 17:30: Work / Training (Mon-Fri)
  if day in 1..5 do
    Repo.insert!(%StudyBlock{
      day_of_week: day,
      start_time: ~T[14:00:00],
      end_time: ~T[17:30:00],
      subject: "Work",
      title: "Work / Training Block",
      color: "#3b82f6",
      icon: "briefcase",
      description: "Separate focus block for work and training responsibilities",
      is_rest_block: true
    })
  end
end

# Sunday (Day 7): Rest Day
Repo.insert!(%StudyBlock{
  day_of_week: 7,
  start_time: ~T[00:00:00],
  end_time: ~T[23:59:59],
  subject: "Rest Day",
  title: "Sunday Rest & Recharge",
  color: "#10b981",
  icon: "sparkles",
  description: "No planned study. Relax, recover, and prepare for Monday with clear energy.",
  is_rest_block: true
})

IO.puts("Successfully seeded study blocks and weekly reviews!")
