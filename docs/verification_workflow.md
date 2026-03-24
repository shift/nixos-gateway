Here is a structured workflow designed for your NixOS router framework. This approach separates **Verification** (Agent 1) from **Documentation** (Agent 2) to ensure strict data integrity.

### Workflow Overview

1.  **Agent 1 (The QA Sentinel):** Analyzes raw test logs/outputs, validates success criteria, extracts timings, and produces a "Trusted Artifact" (JSON/YAML).
2.  **The Handover:** A structured data file containing only verified data.
3.  **Agent 2 (The Scribe):** Reads the Trusted Artifact and generates the user-facing documentation and Test Matrix.

-----

### Agent 1: The QA Sentinel

Prompt file: qa_sentinel_prompt.md

-----

### The Handover (Intermediate Step)

Agent 1 will produce a JSON file. This is crucial because it prevents Agent 2 from "hallucinating" numbers that weren't mathematically verified.

-----

### Agent 2: The Documentation Scribe

Prompt file: scribe.md

-----

### Why this works

  * **Decoupling:** The "Writer" (Agent 2) never sees the raw logs, so it cannot accidentally interpret a failed test log as a success.
  * **Traceability:** The `task_id` is required in the JSON, forcing a hard link between the code/ticket and the final doc.
  * **NixOS Specifics:** NixOS tests often output complex Python-based driver logs. Agent 1 is specifically prompted to parse `nixos-test-driver` outputs.

----

You're job is to deligate the different features to the agents and ensure there work is correct and commited.
