# Manuscript registry

Guidance for the Nano-FFI manuscript deliverables and a live record of where the
paper stands. If anything here conflicts with the repo-root `README.md` or
`CHANGELOG.md`, those win.

## The paper

One software/methods paper, retargeted to several journals: *Nano-FFI: a
comptime-generated, branch-free foreign function interface between Python and
Zig*. The research and every reported number are identical across targets; only
page size, fonts, margins, and reference style change per journal.

## Layout

- `results.py` — the single `compute_results()`; every build imports it, so the
  numbers come from the live ReleaseFast extension and cannot drift. Build the
  extension first (`.\scripts\build_local.ps1` or `zig build -Doptimize=ReleaseFast`).
- `generate_figures.py`, `figures/` — figures regenerated from the live run.
- `manuscript.md` — plain, humanized reading copy (source of the prose).
- `build_docx.py` — renders one Word file per journal into `manuscript/<J>/`.
  Run `python manuscript/build_docx.py` for all, or pass a journal name.

To add a journal, add a profile to `JOURNALS` in `build_docx.py` (folder, font,
size, page, margin). The body and numbers are shared; only front matter changes.

## >>> NEXT SESSION CHECKPOINT (read first) <<<

**The paper is being submitted to JOT first, one venue at a time.** JOT is the
only manuscript built so far (`JOT/Carvajal_JOT_NanoFFI.pdf`, from the official
`jot.cls`). CLEIej and J.UCS official templates are staged in their folders but
their manuscripts are **not built yet**, on purpose.

**At the start of the next session, ASK Felipe whether JOT accepted or rejected
the paper before doing anything else with CLEIej or J.UCS.**
- If JOT **rejected**: build the CLEIej manuscript next (official `cleiej.cls`
  staged in `CLEIej/`; `build_latex`-style script, mirror `build_jot.py`), then
  J.UCS if CLEIej also declines.
- If JOT **accepted**: stop — exclusivity means the paper is placed; do not
  submit elsewhere.
Do not build CLEIej/J.UCS speculatively before that answer.

## Target journals (decided 2026-07-09)

Hard rule from the author: **not JOSS** (Journal of Open Source Software) — it is
excluded as a venue. A Chilean venue is preferred. The modest-profile set below
(peers of *Applications of Modelling and Simulation*) was chosen because
Ingeniare is occupied with another of Felipe's papers. All are non-JOSS.

**Active order:** JOT (built, ready to submit) -> CLEIej -> J.UCS.

| Journal | Country / publisher | Official template | Built? |
|---|---|---|---|
| Journal of Object Technology (JOT) | AITO, jot.fm | `jot.cls` (LaTeX only; Word NOT accepted) | Yes -> `JOT/Carvajal_JOT_NanoFFI.pdf` |
| CLEI Electronic Journal (CLEIej) | CLEI, Latin America | `cleiej.cls` + IEEEtran.bst (LaTeX; also OO/Word) | Staged, not built |
| Journal of Universal Computer Science (J.UCS) | ARPHA / TU Graz | `JUCSWordTemplateV5.docx` + `jucs2e.sty` (needs XeLaTeX) | Staged, not built |

The five earlier profiles in `build_docx.py` (Ingeniare, PeerJ CS, SoftwareX,
Software Impacts, SciCoP) used generic, non-official formatting and are kept only
as reading drafts; the official-template path (JOT/CLEIej/J.UCS) supersedes them.

### Original 5-venue notes (superseded, kept for reference)

| Journal | Country / publisher | Fit | Folder |
|---|---|---|---|
| Ingeniare. Revista Chilena de Ingenieria | Chile (Univ. de Tarapaca) | Chilean, covers Computing & Information Sciences; SciELO/Scopus/DOAJ | `Ingeniare/` |
| PeerJ Computer Science | UK (PeerJ) | OA CS; judges soundness, not "novelty/impact"; no prior-publication gate | `PeerJ_CS/` |
| SoftwareX | Elsevier | Software/tool papers; open code required | `SoftwareX/` |
| Software Impacts | Elsevier | Short Original Software Publication (~3 pages) | `Software_Impacts/` |
| Science of Computer Programming (SciCoP) | Elsevier | Original Software Publications track | `SciCoP/` |

**Primary target: Ingeniare** (satisfies the Chilean preference and the non-JOSS
rule; explicit Computing scope).

**Caveats to check before submitting to the Elsevier software venues:** SoftwareX
and Software Impacts expect the software to have already been used in at least
one scholarly publication. Nano-FFI has not, so Ingeniare and PeerJ CS are the
cleaner first choices; the Elsevier three are staged as alternatives.

## Exclusivity

It is the same paper each time, so only ONE journal may hold it at a time. Submit
sequentially, never in parallel. Update the status table below when anything
changes.

| Journal | Status (2026-07-09) |
|---|---|
| JOT | Built (official jot.cls), ready to submit. NOT yet submitted. |
| CLEIej | Official template staged; manuscript not built (pending JOT outcome). |
| J.UCS | Official template staged; manuscript not built (pending JOT outcome). |
| Ingeniare | Occupied by another paper of Felipe's; not in play now. |
| PeerJ CS / SoftwareX / Software Impacts / SciCoP | Superseded reading drafts only. |

## AI-disclosure obligation (resolve before submission)

The manuscript text was drafted with generative-AI assistance and then edited to
read in the author's own register (via `/article-humanizer` and `/article-audit`).
Style-editing is NOT a substitute for disclosure. COPE, Elsevier (SoftwareX,
Software Impacts, SciCoP), and PeerJ all require a generative-AI-use disclosure
statement (typically near the References or in Methods); AI cannot be an author.
Ingeniare's policy should be confirmed directly. **Add the required disclosure
statement to the target journal's submission before sending.** This is the
author's call and is intentionally left for Felipe to confirm per venue.

## Conventions

English, plain ASCII (no emojis, avoid em-dash-as-aside in generated prose),
numbers reproducible from `results.py`. When a submission status changes, update
the table above in the same edit.
