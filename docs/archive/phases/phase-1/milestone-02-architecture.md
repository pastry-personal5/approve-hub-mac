# P1-M2: Software Architecture, technical approach

Status: Archived

How the decisions and the doc in [milestone-02-overview.md](milestone-02-overview.md) get made. The result lives in `docs/architecture.md`, not here, so this doc describes the process only.

## Inputs

- The six P1-M1 research notes and the product-scope proposal.
- AGENTS.md "Undecided", as P1-M1 left it, and the owner's interview decisions of 2026-10-07 in the [changelog](changelog.md). Several are already decided, for example the background server with the GUI as a client, macOS 26 or later, and own-Mac distribution, so the decision order below starts from them.
- The constraints in AGENTS.md: the decided stack, approval logic kept out of views, typed errors with no force unwrap outside tests, no `phase` or `MVP` in code names, and dependencies compatible with Apache-2.0.

## Method

1. **Order the decisions.** Decisions depend on each other, so take them in this order:
   1. Hosting model.
   2. Transport and API style.
   3. Security model.
   4. Request lifecycle and state machine.
   5. Module and target layout.
   6. Persistence, concurrency and test strategy.

   Add the remaining "Undecided" items where they fit. Re-order only if a note shows a different dependency.
2. **One decision at a time.** For each item, present the options from the P1-M1 note with trade-offs and a recommendation. The owner decides. Record it in AGENTS.md "Decided" and as a changelog entry before moving on.
3. **Name the API server** once the hosting model is decided, because that choice can affect what the name refers to (a process, a service, a module). Propose two or three candidates with rationale.
4. **Draft `docs/architecture.md`** with the required headings first, then fill each section as its decision lands. Link to the research notes for evidence instead of copying them. Include one component diagram.
5. **Reconcile the skeleton** with the chosen target layout. A restructure needs the owner's approval first.
6. **Dependencies.** List every dependency or build tool the architecture needs, with its license. None is added without the owner's approval.
7. **Wrap up:** the owner reviews the doc, the gate runs once, and the docs are updated. Then archive the research notes whose conclusions became decisions, as AGENTS.md "Archive, don't delete" describes, and fix the links to them. Keep a note active only if some of its conclusions are still undecided.

## Risks

- A P1-M1 note may leave a choice that needs more evidence. Either run a small follow-up experiment, or defer the item with the owner's approval and a reason.
- The owner may change the API server's scope, for example by deciding the GUI can't be a pure client. Log the change in [changelog.md](changelog.md) and update the affected sections.
