# Hardening Roadmap

## Purpose

This roadmap turns **Conversation Analyzer** into the reference implementation for a Core-backed Genesys desktop investigation tool.

The application is intended to be a **fast operator frontend** for pivoting through large amounts of conversation data over the course of an investigation, not a second API client and not a second normalization engine.

The target architecture is:

- **`Genesys.Core`** performs all Genesys Cloud extraction, async job handling, paging, retry, normalization, run manifests, and reusable analysis primitives.
- **A local embedded case database** stores structured Core outputs plus analyst-added investigative state for fast multi-day workflows.
- **The WPF frontend** drives acquisition, loads the local case database, enables rapid pivots, and produces exports and summaries.

## Non-Negotiable Architecture Guardrails

Scope: these guardrails apply to every session below and must be treated as acceptance criteria for the project, not optional design preferences.

Task: all conversation dataset extraction must flow through **`Genesys.Core`** public entry points such as `Invoke-Dataset` and related reusable module primitives.

Task: the WPF application must not own or duplicate direct Genesys Cloud extraction logic for conversation datasets, including async job submission, polling, paging, or retry behavior.

Task: reusable transformation or normalization logic discovered during this project must be implemented in `Genesys.Core`, not only in the frontend.

Task: the frontend may own only app-specific ingestion, local indexing, case workflow state, saved views, notes, findings, reporting, and UX-specific derived projections.

Task: all local storage must be retention-aware, purgeable, and attributable to a case and a Core run provenance record.

Validation: before each session is considered complete, confirm its implementation does not introduce a new script-local extraction path or duplicate canonical module logic.

Documentation: every repo document must describe the application as a **Core-backed frontend with a local case store**, not as an independent API analyzer.

## Current-State Reality Check

Scope: establish the factual starting point so the roadmap measures forward progress against reality rather than wishful thinking.

Task: treat the current script-local REST flow in `GenesysConvAnalyzer.ps1` as technical debt to be removed or isolated, not as the long-term foundation.

Task: treat the existing `Genesys.Core` module structure, dataset handlers, normalization pipeline, manifests, and event outputs as the canonical platform base to extend.

Task: treat the existing normalized JSONL outputs and analysis artifacts under `out-test*` as evidence that the module-first pattern is already partially present and should now be promoted into the frontend architecture.

Validation: capture a short current-state note in the repo describing what is still script-local today, what already exists in `Genesys.Core`, and what the first migration seam will be.

Documentation: update any stale wording that currently implies the script depends on `Genesys.Core` while still performing its own acquisition path.

## Session 1: Core-First Architecture Lock — **COMPLETE**

> **What was delivered:** `App.CoreAdapter.psm1` is the sole module that imports `Genesys.Core`, calls
> `Assert-Catalog`, and calls `Invoke-Dataset`. Gate A (startup), Gate B (run invocation), Gate D (import
> boundary), and Gate E (auth boundary) are all enforced. The compliance suite and architecture test suite
> (~92 checks total) verify these invariants on every run. No script-local extraction path exists.

Scope: establish the final architectural direction immediately so no further work hardens the wrong layer.

Task: rewrite the hardening target for the repo so the application is explicitly defined as a **frontend UX over `Genesys.Core` plus a local case database**.

Task: identify and document the exact script-local functions that currently duplicate module responsibilities and mark them as migration targets.

Task: define the first end-to-end module-backed path that must replace the current script-local acquisition flow.

Task: make `ModulePath` a real validated dependency at startup or remove any implication that it is already active.

Validation: confirm the repo contains an explicit statement that conversation extraction belongs to `Genesys.Core` and that no future session depends on expanding script-local extraction logic.

Documentation: update roadmap, repo notes, and inline commentary so they all reflect the same architecture with no mixed messaging.

## Session 2: Core Output Contract for Conversation Data — **COMPLETE**

> **What was delivered:** `App.CoreAdapter.psm1` formalizes the contract with `Get-RunManifest`,
> `Get-RunSummary`, `Get-RunEvents`, `Get-RunStatus`, and `Get-RecentRunFolders`. Two dataset keys are
> locked: preview (`analytics-conversation-details-query`) and full (`analytics-conversation-details`).
> The index module (`App.Index.psm1`) extracts the stable conversation entity shape
> (id, direction, mediaType, queue, disconnect, hasMos, hasHold, segmentCount, participantCount, durationSec)
> from Core-produced JSONL. Architecture tests ARCH-10 through ARCH-12 and ARCH-25 through ARCH-28 guard
> the artifact contract.

Scope: define the stable contract between `Genesys.Core` and Conversation Analyzer before more UI or storage work is added.

Task: document the expected `Invoke-Dataset` contract for the conversation dataset used by this application, including required inputs, output folder layout, manifest shape, summary shape, event files, and entity files.

Task: define the minimum stable conversation entities the frontend depends on, including conversations, participants, sessions, segments, metrics, and attributes.

Task: include provenance and compatibility fields such as `run_id`, dataset key, extraction window, schema version, normalization version, environment or org identifier, and generation timestamp.

Task: define how the frontend will detect and reject incompatible schema or normalization versions.

Validation: confirm a sample Core run can be validated against the documented contract using the existing normalized output artifacts already present in the repo.

Documentation: add a concise contract document and ensure the roadmap references that contract as the source of truth for importer and UI assumptions.

## Session 3: Module-Backed Acquisition Replaces Script-Local REST — **COMPLETE**

> **What was delivered:** `App.UI.ps1` starts preview and full runs by launching a background runspace
> that re-initializes `App.CoreAdapter.psm1` and calls `Start-PreviewRun` / `Start-FullRun`. The UI
> owns only parameter collection, progress polling (2-second DispatcherTimer), cancellation, and result
> loading. No direct `Invoke-RestMethod` calls exist for conversation data. Architecture tests ARCH-06
> through ARCH-09 enforce this boundary. The Run Console tab displays live events from `events.jsonl`
> during a run and the full diagnostics dump on completion.

Scope: remove the application's current role as a bespoke API client for conversation extraction.

Task: replace the existing script-local acquisition flow in `GenesysConvAnalyzer.ps1` with a module-backed call path using `Invoke-Dataset` and any required public module helpers.

Task: remove or isolate direct REST helpers related to conversation extraction so they cannot remain the default operational path.

Task: make the UI drive dataset input collection, request preview, submission intent, and job status display without owning the underlying transport behavior.

Task: preserve engineer visibility into what is being requested by exposing Core input parameters and emitted run metadata rather than raw duplicated request code.

Validation: run the same conversation query through the new module-backed path and confirm the produced run artifacts and record counts match expected Core behavior.

Documentation: update script synopsis, comments, and repo notes to state exactly which acquisition path is now active and what legacy code remains only as temporary migration scaffolding.

## Session 4: Local Embedded Case Database Foundation — **COMPLETE**

> **What was delivered:** `App.Database.psm1` now owns all SQLite interaction, DLL resolution,
> schema creation, case lifecycle primitives, Core run registration, import tracking, and conversation
> storage. `App.ps1` initializes the case store at startup (Gate F), and the UI surfaces case-store
> availability and active-case selection. SQLite is the default local case database and the schema can be
> recreated from scratch on a clean machine.

Scope: introduce the app's durable local workflow layer so investigators can work from structured data over multiple days without re-querying.

Task: adopt **SQLite** as the default embedded database for the application unless a proven technical blocker appears.

Task: define the initial schema around **cases**, **Core runs**, **dataset imports**, and the imported conversation entities needed for fast pivots.

Task: model the case lifecycle explicitly, including case creation, active investigation, refresh, export, closure, archive or purge, and expiry handling.

Task: ensure the database is treated as a **case-oriented analytical cache** rather than a source-of-truth warehouse.

Validation: create a schema v1 that can persist at least one imported normalized conversation run plus a case record and can be recreated from scratch on a clean machine.

Documentation: add a database design note describing why SQLite was chosen, what the case scope means, and what the database is intentionally not.

## Session 5: Core-to-Database Importer Pipeline — **COMPLETE**

> **What was delivered:** `Import-RunFolderToCase` validates the Core artifact contract
> (`manifest.json`, `summary.json`, `data/*.jsonl`), enforces supported dataset keys, rejects explicit
> schema/normalization major versions other than `1`, registers or refreshes the `core_runs` provenance
> row, and imports conversation rows into SQLite in batches within a single transaction. Re-importing the
> same case/run marks prior completed imports as `superseded`, deletes prior conversation rows for that
> case/run, and replaces them with the current snapshot. The UI exposes active-case management plus an
> `Import Loaded Run` action, and the importer behavior is documented in repo notes.

Scope: build a real importer rather than a loose file loader so the local store is trustworthy and repeatable.

Task: implement an importer that reads Core-produced manifest and JSONL outputs, validates compatibility, and writes records into SQLite within a controlled transaction boundary.

Task: record provenance for every import, including Core run id, dataset key, import time, source window, record counts, and any schema or normalization versions.

Task: decide and implement initial import semantics for duplicate records, incremental refreshes, superseded imports, and import rollback on failure.

Task: surface import warnings and failures clearly in a structured operation log so engineers can trust what has and has not been loaded.

Validation: import an existing normalized conversation run from the repo fixtures into a new local database and verify entity counts, indexes, and provenance rows are correct.

Documentation: add importer behavior notes that explain supported artifact shapes, compatibility checks, and failure semantics.

## Session 6: Case Workflow State and Retention Controls — **COMPLETE**

> **What was delivered:** schema v2 adds case-workflow tables for tags, bookmarks, findings, saved views,
> report snapshots, and audit history. The database layer now exposes retention-aware case operations for
> expiry updates, close, archive, purge-ready, and purge. Archive clears imported Core data while
> preserving analyst work product; purge clears imported data plus workflow state while retaining the case
> shell and audit trail. The case-management dialog now supports notes, tags, saved views, and lifecycle
> actions with audit visibility.

Scope: preserve investigative momentum across days while keeping data hygiene strict and explicit.

Task: add database support for analyst-created value such as notes, tags, bookmarks, findings, saved views, and report snapshots tied to a case.

Task: define retention fields and rules for active, expiring, archived, and purge-ready cases.

Task: add purge and optional archive workflows that clear local data at case close or after expiry according to policy.

Task: ensure purge and archive actions are auditable inside the application so users understand what was removed and when.

Validation: create a case, import data, add notes and saved views, then close and purge the case and verify data removal and purge audit behavior work as designed.

Documentation: add a case lifecycle and retention note that explains the intended multi-day incident workflow and the flush-clean expectation at case end.

## Session 7: High-Volume Pivot UX Over the Local Store

> **Pre-work completed:** The existing JSONL index (byte-offset seek, 64 KB buffered reader, UTF-8 BOM
> handling) and in-memory paging in `App.Index.psm1` / `App.UI.ps1` deliver a functional pivot UX over
> Core run folders today. Filters for direction, media type, queue, and free-text search are wired. This
> work is superseded but not discarded — the index strategy informs the SQLite column selection. When
> SQLite is in place this session rebuilds the same UX paths against the database layer.

Scope: make the application fast and useful for real investigation work by driving the UI from the local database instead of large in-memory raw collections.

Task: refactor the main conversation grid and detail views to query the local database or efficient in-memory projections derived from it, rather than repeatedly traversing full raw collections.

Task: optimize the UI for the pivots investigators actually use, such as time range, queue, division, ANI, DNIS, agent, disconnect patterns, transfer behavior, participant structure, and selected metric summaries.

Task: design the interaction model around cases, saved views, findings, and evidence collection rather than only a one-time load-and-grid experience.

Task: keep the workflow centered on rapid pivoting of large datasets while preserving selection context and detail inspection.

Validation: load a realistically large local case dataset and verify common filter and selection paths remain responsive without re-querying Genesys Cloud.

Documentation: update usage notes to describe the case-driven pivot workflow and the fact that most interactive analysis now happens over the local case store.

## Session 8: Local Query Performance and Index Hardening

> **Pre-work completed:** The JSONL byte-offset index delivers O(pageSize) record retrieval without full
> dataset loads. StreamReader is used throughout; `Get-Content` is banned by architecture test ARCH-17/21.
> The buffered 64 KB chunk reader in `_ReadFileLines` handles large files efficiently. These patterns carry
> forward as the design rationale for SQLite index column selection.

Scope: harden the local analytical store so it remains swift under the size and repetition expected in real incident workflows.

Task: add practical indexes for the most common investigation paths, especially conversation id, time range, queue, division, ANI, DNIS, agent-related fields, and case membership.

Task: review schema design for columns that should remain normalized versus fields that should be materialized or side-car JSON for performance and simplicity.

Task: add importer-side batching and transaction strategies that keep large imports predictable.

Task: add user-visible counts and timings for imports and major query pivots so performance regressions are visible.

Validation: run repeated import and pivot tests against larger fixture data and verify query performance remains acceptable for day-to-day operator use.

Documentation: add a concise performance note describing the intended dataset scale, indexing strategy, and any still-known limits.

## Session 9: Structured Telemetry Across Core, Import, and UX

> **Pre-work completed:** The Run Console tab (`DgRunEvents`, `TxtDiagnostics`, `BtnCopyDiagnostics`) is
> wired and functional. Live polling reads `events.jsonl` during a run via `Get-RunEvents`. On completion
> `Get-DiagnosticsText` assembles manifest + summary + last 10 events. Error streams from the background
> runspace surface in `TxtDiagnostics`. This session extends that foundation to cover import, case
> actions, and export operations.

Scope: make the end-to-end workflow observable so engineers and maintainers can trust the tool when incidents are messy and time matters.

Task: unify the frontend operation log with structured event records for Core invocation, import, case actions, saves, exports, refreshes, and purge operations.

Task: preserve Core run metadata and events as first-class references inside the application so investigators can trace findings back to source runs.

Task: convert silent catches and ambiguous error text into explicit warning or error events with actionable context.

Task: emit counts and durations for retries, poll cycles, imported records, skipped records, failed rows, query timings, and export outcomes where appropriate.

Validation: execute an end-to-end flow from case creation through import, pivoting, export, and purge and inspect the resulting telemetry for completeness and clarity.

Documentation: add a telemetry note that states exactly what artifacts and local records are produced today and what fields are available for troubleshooting.

## Session 10: Export, Evidence Pack, and Report Workflow

> **Pre-work completed:** `App.Export.psm1` delivers streaming `Export-RunToCsv` (line-by-line,
> no full dataset load), `Export-PageToCsv` for the current grid page, and `Export-ConversationToJson`
> for a single record. All three are wired in `App.UI.ps1`. This session adds case-level exports, HTML
> output, and the evidence-pack concept.

Scope: make the application useful at the end of an investigation, not only during exploration.

Task: design exports around the case model so engineers can produce a coherent summary of findings, selected conversations, saved filters, counts, and analyst notes.

Task: support at least CSV and HTML outputs in a way that reflects the case state and selected evidence rather than dumping raw rows without context.

Task: preserve provenance in exports so management or incident partners can see what Core run and time window the report was based on.

Task: add a lightweight evidence-pack concept that groups the conversations, notes, and summary needed to hand off or brief others.

Validation: create a case report from a populated local case and confirm it includes enough context to support a real incident handoff or management summary.

Documentation: update repo documentation to describe supported export modes, what is included in them, and the provenance fields users should expect.

## Session 11: Automated Test Coverage for the Reference Pattern

> **Pre-work completed:** `tests\Test-Compliance.ps1` (~60 static Gate D/E checks) and
> `tests\Invoke-AllTests.ps1` (32 architecture invariants covering startup, extraction boundary,
> dataset keys, indexing, export streaming, auth containment, run artifacts, XAML nuances, config,
> and strict mode) are fully implemented and exit 0 or 1 cleanly. This session adds Pester coverage
> for the importer, case lifecycle, and database logic once those layers exist.

Scope: harden the application as the intended flagship pattern for future Core-backed frontend apps.

Task: add Pester coverage for the importer, case lifecycle logic, retention handling, query assembly into Core input parameters, schema validation, and export shaping.

Task: add module-side tests where new reusable logic was promoted into `Genesys.Core` during this roadmap.

Task: create fixture sets representing realistic normalized conversation runs, incremental refresh situations, malformed artifact cases, and purge scenarios.

Task: make test execution straightforward from the repo root and ensure failures clearly identify whether the break is in Core integration, import behavior, database logic, or UX-adjacent pure functions.

Validation: run the full Pester suite and confirm each major architectural layer has meaningful coverage, especially the Core-to-DB contract and case retention flows.

Documentation: add a test note that explains entry points, fixture locations, and what categories of behavior are currently covered.

## Session 12: Reference Implementation Cleanup and Blueprint Packaging

Scope: finish the project as a clean flagship that can be copied in pattern, not in accidental complexity.

Task: remove dead code and stale comments from the old script-local acquisition path once the module-backed flow is proven and stable.

Task: identify which pieces created during this work are reusable across future apps and promote them into explicit blueprint documentation.

Task: produce a concise reference architecture document describing the shared pattern of **Core extraction**, **local case database**, and **frontend investigation UX**.

Task: capture the rules for what belongs in `Genesys.Core` versus what remains app-specific so future smaller dataset apps do not reinvent the same logic in new corners.

Validation: review the repo at the end of the roadmap and confirm it reads like a coherent reference implementation rather than a partially migrated one-off.

Documentation: update all repo documentation so it accurately describes the application as a flagship Core-backed frontend pattern for conversation analysis and future dataset apps.

## Definition of Success

Scope: these are the end-state behaviors the roadmap is intended to achieve.

Task: an engineer can open a case, request conversation data through `Genesys.Core`, ingest the normalized output into a local SQLite case store, and begin pivoting immediately.

Task: the engineer can continue investigating over multiple days without re-querying the same large dataset, while adding notes, bookmarks, tags, findings, and saved views.

Task: the engineer can refresh the case with additional Core runs when needed without losing provenance or prior investigative work.

Task: the engineer can generate a coherent export or report with traceable run metadata and then archive or purge the case according to policy.

Validation: run a realistic incident workflow from start to finish and verify the application behaves as a trustworthy, fast, and maintainable frontend rather than as a custom API extractor.

Documentation: keep this definition of success visible in the repo so future roadmap changes are tested against it instead of drifting into convenience-led architecture.
