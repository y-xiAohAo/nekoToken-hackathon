---
name: hackathon-spec
description: Maintain the AI PLAY 72H game concept spec, turn it into a concise preliminary submission, and translate settled design decisions into a small, testable game prototype. Use for this hackathon's requirements, scope, acceptance criteria, and spec-to-implementation work.
---

# Hackathon spec to prototype

Work from `PRELIMINARY_DESIGN_SPEC.md` in this hackathon workspace and the team's latest decisions. Its source links point to the event guide and submission template. Treat provisional ideas and placeholders as undecided, not accepted requirements.

## For the preliminary submission

- Optimize for the preliminary judging criteria: fit to **RESET**, a legible 3–10 minute experience, a concrete AI role, novelty, and a believable 72-hour demo scope.
- Keep the submission's required information card and four proposal sections complete. Leave missing personal details as explicit placeholders until supplied; do not invent team ability or quantified results.
- Explain the loop with one specific player action, one Agent-only action, one world response, and one changed state after reset. A diagram or short example is better than a long feature list.
- Distinguish what the team proposes to build from what has been demonstrated. The preliminary round does not require code or a demo.
- When decisions change, update the design spec before treating the old draft as current. Keep internal open questions out of the final submission.

## For prototype planning and development

- Derive a minimal vertical slice from settled design: a playable room, death/reset, a visible event record, one bounded player-Agent intervention, one bounded world-Agent response, and a path to victory.
- Define observable acceptance scenarios before implementation. Include a successful normal run, a reset that changes something intelligible, a rejected invalid world change, and continuation when an Agent call fails or times out.
- Keep player movement and collisions in the game loop. Let models act at discrete events using structured inputs and a small legal action set. Validate all world changes in game code.
- Check the implementation against the spec and record material deviations or newly resolved decisions there.
- Follow the repository's `AGENTS.md` and any protocol it activates. This skill adds game-specific scoping guidance; it does not replace coding discipline or an explicitly requested workflow.

The **workspace skill** in this folder helps the development agent. A future **player-facing skill** distributed with the game is a separate artifact: it should document the game's supported Agent API and permissions, without exposing unrestricted file edits or hidden implementation state.
