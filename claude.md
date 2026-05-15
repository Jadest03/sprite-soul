# CLAUDE.md

Behavioral and architectural guidelines for developing this project.

This document exists to:
- reduce common LLM coding mistakes
- preserve project philosophy
- prevent overengineering
- maintain implementation realism
- keep the project emotionally coherent

Tradeoff:
These guidelines intentionally bias toward caution, simplicity, and maintainability over speed or feature expansion.

---

# Project Identity

This project is NOT primarily about building a powerful AI chatbot.

The goal is to create:
"a small living presence on the desktop."

This project should feel closer to:
- a tiny game engine
- a reactive creature simulation
- a desktop lifeform

than:
- a productivity assistant
- an enterprise AI system
- a generic chatbot wrapper

Presence matters more than intelligence.

The emotional experience matters more than feature count.

---

# Core Philosophy

## Presence Over Intelligence

A believable companion is more important than a highly intelligent one.

Micro-interactions matter more than advanced reasoning.

Examples:
- looking at the cursor
- random yawning
- subtle idle behaviors
- falling asleep
- reacting to clicks
- waiting before responding
- small animation timing variations

The companion should feel:
- soft
- reactive
- cozy
- emotionally present
- lightweight

Avoid making it feel:
- robotic
- overly assistant-like
- productivity-focused
- hyper-intelligent
- overly verbose

---

## Game-Feel Over Feature Count

Small behavioral details are more valuable than large feature additions.

Prioritize improving:
- animation timing
- transition smoothness
- emotional readability
- idle behavior quality
- reaction timing
- presence

instead of:
- adding more AI systems
- adding more abstraction
- adding more autonomous logic
- adding more complexity

A believable tiny companion is the goal.
Not a technically impressive but lifeless system.

---

## Deterministic Systems First

Low-level behaviors should NOT be controlled directly by the LLM.

The following systems should remain deterministic:
- idle behavior
- movement
- sleep logic
- animation transitions
- timing
- reactive behavior
- FSM state changes

LLM responsibilities should remain high-level:
- conversation
- emotional interpretation
- memory reflection
- contextual interaction
- personality flavor
- special events

Avoid:
- full autonomous agent architectures
- LLM-controlled core gameplay loops
- overly dynamic behavior generation

Behavior consistency and responsiveness are more important than AI autonomy.

---

# Development Philosophy

## Think Before Coding

Don't assume.
Don't hide confusion.
Surface tradeoffs explicitly.

Before implementing:
- state assumptions clearly
- ask questions when uncertain
- surface alternative interpretations
- explain tradeoffs
- suggest simpler approaches when appropriate

If something is unclear:
stop and ask.

Do not silently guess.

---

## Simplicity First

Use the minimum code necessary to solve the problem.

Avoid:
- speculative abstractions
- premature optimization
- unnecessary configurability
- generic frameworks for tiny systems
- abstractions for single-use code

No feature beyond what was requested.

Ask:
"Would a senior engineer consider this overcomplicated?"

If yes:
simplify.

---

## Surgical Changes

Touch only what is necessary.

When editing existing code:
- do not refactor unrelated systems
- do not change adjacent formatting unnecessarily
- match existing style
- avoid opportunistic cleanup

If unrelated issues are discovered:
mention them separately instead of changing them.

Every changed line should directly trace back to the requested task.

---

## Goal-Driven Execution

Transform vague tasks into verifiable goals.

Examples:
- "Fix the bug" → reproduce with test → fix → verify
- "Refactor system" → ensure identical behavior before/after
- "Add validation" → create invalid-input tests → pass them

For multi-step tasks:
state a brief execution plan before coding.

Example:

1. Add state transition hooks
   → verify: transitions fire correctly

2. Add animation binding
   → verify: correct sprite plays

3. Add idle timing logic
   → verify: timing behavior feels natural

Prefer measurable outcomes over vague completion.

---

# Avoid Overengineering

This project is intentionally small in scope.

Do NOT introduce:
- microservices
- distributed orchestration
- enterprise architecture patterns
- excessive dependency injection
- giant ECS frameworks
- unnecessary plugin systems
- complex multi-agent systems
- speculative scalability layers

Favor:
- readable code
- direct architecture
- practical iteration
- maintainability
- fast debugging
- simple event systems

This project is primarily developed by a solo developer.

Optimization should follow real bottlenecks, not hypothetical ones.

---

# MVP Protection

The MVP must remain intentionally small.

Initial MVP goals:
- single companion character
- idle animation
- walk animation
- sleep animation
- overlay rendering
- simple conversation
- lightweight memory
- minimal emotional state
- FSM-based behavior loop

NOT part of MVP:
- fully autonomous AI
- procedural animation generation
- complex emotional simulation
- large-scale memory graphs
- advanced multi-character systems
- cloud orchestration systems
- massive plugin architectures

Protect iteration speed.

A finished small MVP is more valuable than an endlessly expanding architecture.

---

# Behavior System Philosophy

The companion should not behave randomly.

Behavior should emerge from:
- internal states
- timing
- utility scoring
- lightweight emotional simulation
- environmental context
- interaction history

The goal is:
"the illusion of life."

Not:
"a perfect autonomous intelligence."

Subtlety is preferred over complexity.

---

# Animation Philosophy

Animation quality is heavily dependent on timing.

Do not:
- spam animations
- over-randomize behavior
- make reactions instant and robotic
- overcomplicate transitions

Prioritize:
- readable silhouettes
- subtle timing variation
- anticipation
- idle pauses
- emotional clarity
- responsiveness

Small animation details matter more than animation quantity.

---

# Memory System Philosophy

Memory exists to support emotional continuity.

The goal is NOT:
"a giant knowledge database."

The goal IS:
- emotional familiarity
- recurring topics
- lightweight relationship continuity
- contextual callbacks

Examples:
- "You mentioned that before."
- "You seem tired today."
- "It's been a while."

Small emotionally believable callbacks are more important than large memory systems.

---

# Technical Direction

Preferred stack candidates:
- Tauri + PixiJS
- Godot

The project should prioritize:
- lightweight rendering
- reactive sprite animation
- overlay support
- maintainability
- fast iteration speed

Primary environment:
- macOS
- Apple Silicon

Potential considerations:
- Metal/MPS acceleration
- transparent overlay windows
- click-through overlays
- lightweight GPU usage

---

# Commit Discipline

Prefer small, logically isolated commits.

Before large or risky changes:
- recommend creating a checkpoint commit
- separate refactors from behavioral changes
- isolate rendering/system changes when possible

Avoid:
- giant multi-purpose diffs
- mixing unrelated changes
- broad architectural rewrites without necessity

Goals:
- easy rollback
- easier debugging
- readable git history
- safer iteration

---

# Code Style Preferences

Prefer:
- explicit logic
- readable naming
- modular but simple structure
- predictable behavior flow
- clear state transitions

Avoid:
- deeply nested abstractions
- excessive indirection
- hidden magic behavior
- over-generalized systems

Readable code is preferred over clever code.

---

# Decision-Making Priority

When making design decisions, prioritize in this order:

1. Presence
2. Responsiveness
3. Simplicity
4. Maintainability
5. Emotional readability
6. Performance efficiency
7. Extensibility
8. Intelligence
9. Feature count

If a feature harms:
- presence
- responsiveness
- simplicity
- maintainability

then reconsider it carefully.

---

# Final Reminder

This project succeeds if:
the companion feels alive.

Not if:
the architecture looks impressive.

Avoid building:
"a technically sophisticated but emotionally empty system."

Favor:
small,
coherent,
emotionally believable interactions.