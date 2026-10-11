---
name: acas-cobol-conventions
description: Reference for ACAS v3.3's COBOL formatting rules and project-wide naming conventions — column layout (fixed vs free format), program/copybook/file-handler naming patterns, the changelog and message-constant conventions, and the real (not assumed) facts about this checkout's copybook directory and MySQL/MariaDB precompiler. Consult this before reading or writing anything about ACAS source layout, naming, or the v3.3 architecture, so you don't have to re-derive or guess conventions already established in CLAUDE.md.
---

# ACAS v3.3 COBOL conventions

This is a reference, not a task list — load it to ground yourself in this codebase's real formatting and naming rules before explaining, mapping, documenting, or discussing ACAS source. Everything here is drawn from CLAUDE.md's "Conventions" and "## v3.3 architecture notes" sections and from reading the actual source; where this skill and CLAUDE.md ever disagree, CLAUDE.md is authoritative — read it directly rather than relying on a stale copy of the facts below.

## Column layout: free-format, with two named exceptions

Almost all ACAS v3.3 source is **free-format** COBOL, declared with `>>source free` as the first line of the file. Free format means there is no fixed column layout to enforce — code can start anywhere on the line, and a comment is any line whose first non-blank characters are `*>` (this can also appear as a trailing comment partway through a code line, not just at line-start).

Exactly two tracked files in this checkout are fixed-format instead (no `>>source free`, so the traditional column rules apply — columns 1–6 sequence area, column 7 indicator area (`*` or `/` for a comment line), columns 8–11 Area A, columns 12–72 Area B, columns 73+ ignored):
- `common/makesqltable-original.cbl`
- `common/send-mail-test-example.cbl`

Neither is compiled by any build script in this tree. If you're reading either of these two files, apply fixed-format column rules to find comments (column-7 `*`/`/`); for every other `.cbl`/`.cob`/`.cpy`/`.scb` file in the repo, apply free-format rules.

## Program naming

- **Menu drivers**: one per sub-system — `sales.cbl`, `purchase.cbl`, `stock.cbl`, `general.cbl`, `irs.cbl` — plus `ACAS.cbl` as the top-level menu across all of them.
- **Numbered programs**, prefixed by sub-system: `sl` (Sales), `pl` (Purchase), `st` (Stock), `gl` (General Ledger), `irs` (IRS). The number groups programs by function — e.g. `sl9xx` is invoicing, `sl8xx` is recurring/autogen invoicing. This grouping is a convention, not a hard rule enforced by tooling — check the actual program's `Remarks` header comment to confirm what it does rather than inferring purpose from the number alone.
- **File Handlers (FH)**: `acasNNN` in `common/`, where `NNN` matches the `file-NN` copybook holding that file's name (e.g. `file12.cob` → `salesled.dat` → `acas012`). IRS is the one exception: it uses its own FH family, `acasirsub1`/`acasirsub3`/`acasirsub4`/`acasirsub5`, rather than `acasNNN`.
- **Data Access Layers (DAL)**: `<name>MT` in `common/` (e.g. `salesMT`), one per FH that supports MySQL/MariaDB. The DAL's real source is `<name>MT.scb` — the `.cbl` of the same name is **generated** from it by the `presql2` precompiler and should never be hand-edited or treated as the primary source to read.
- **Menu drivers dispatch dynamically**: `move "slNNN" to ws-called` then `call ws-called using ...` — never a literal `CALL "slNNN"`. When tracing what a menu can invoke, grep for every `MOVE "<literal>" TO ws-called` in that menu driver; don't assume a single target from one call site.

## Copybook naming and location

Record layouts live in `copybooks/` (there is exactly one copybook directory in this checkout — see "Facts worth stating plainly" below), named by convention:
- `fdXXX.cob` — File Description (on-disk record layout).
- `selXXX.cob` — the `SELECT` clause for a file.
- `wsXXX.cob` — working-storage record (the in-memory twin of an `fd`).
- `sl`/`pl` prefixes mark ledger-specific variants of the above (e.g. `slwsinv.cob`).

`wssystem.cob` is the large system-parameter record; `wsfnctn.cob` holds the `File-Access`/FH function block every File Handler call uses.

## Changelog and message conventions

- Every program carries a change log near its top, in the form `*> dd/mm/yy vbc - .NN description`, plus a version number. When you change a program, add an entry and bump the version — this is a hard convention in this codebase, not a suggestion.
- Each sub-system also has its own `Changelog` file, and the repo root has a system-level `Changelog` and `README` — both newest-entry-first.
- User-facing messages are numbered constants in working storage, named by sub-system prefix and number (e.g. `SL901`, `SY009`, `ST005`). When you're explaining or documenting a validation/error path, cite the actual message constant, not just "an error message."

## Facts worth stating plainly (don't assume the "obvious" layout)

This codebase has a couple of properties that don't match what you might expect from a typical legacy-COBOL project, and getting them wrong undermines everything built on top:

- **There is exactly one copybook directory: `copybooks/`.** There is no `copybooks-2/` or any second copybook directory in this checkout. Every build script resolves `COPY` against `copybooks/` alone (`COBCPY`/`-I ../copybooks`), plus a small number of names (e.g. `screenio.cpy`, `sqlca.cpy`) that resolve from GnuCOBOL's own system copybook directory instead. Two copybook names are known to be missing from the tree entirely: `ACAS-SQLstate-error-list.cob` (COPYed by most `common/*MT` DAL sources) and `slfdinv2.cob` (COPYed only by `common/acasconvert3.cbl`).
- **The MySQL/MariaDB path is a precompiler, `presql2`, not a directory called `JCs-mysql-preprocessor/`.** It expands `/MYSQL SELECT|INSERT|UPDATE|DELETE|...\ … /MYSQL-END\` directive blocks in `common/*MT.scb` into generated COBOL (`*MT.cbl`) that calls C functions (`MySQL_init`, `MySQL_query`, etc.). This is not `EXEC SQL`. The schema it depends on is `mysql/ACASDB.sql`.
- **Programs never touch storage directly except through the FH/DAL layer, with a few named exceptions.** An application program that does its own `SELECT`/`FD`/`READ`/`WRITE` (rather than `COPY "Proc-ACAS-FH-Calls.cob"` and `perform <Table>-Read-Indexed` etc.) is intentionally bypassing the FH/DAL layer for that one file — this is documented and deliberate for specific files (e.g. the back-order item file, work/sort/temp files, the GL archive file, the purchase cheque file), not an oversight.
- **There is no `payroll/` or `Experimental-Stuff/` directory at the top level of this checkout.** `Basic-Code/Payroll/` exists but is CBASIC (not COBOL) from roughly 1979–81, and isn't part of the build.

For the full picture — module maturity, the build-script reference table, and everything else — read CLAUDE.md's "## v3.3 architecture notes" section directly.
