# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ACAS (Applewood Computers Accounting System) v3.3 — a GnuCOBOL (3.2) accounting suite, maintained by Vincent B. Coen. Sub-systems: IRS (incomplete-records bookkeeping), General Ledger, Sales Ledger, Purchase Ledger, Stock Control. Data is stored either in COBOL ISAM/flat files or in MySQL/MariaDB (the only RDBMS supported), selected at runtime by the system parameter file.

The build and runtime target is Linux with bash. This checkout is on Windows, so the `.sh` build scripts won't run here unless GnuCOBOL (`cobc`) is available, for example via WSL. This directory is not a git repo (upstream uses SourceForge SVN/CVS).

## Build

Run the top-level scripts from the repo root. Each one `cd`s into each sub-system directory and runs that directory's script:

- `./comp-all.sh`: full build with RDBMS. Needs the MySQL/MariaDB client libs at `/usr/local/mysql/lib`, `cobmysqlapi.o`, and the `presql2` precompiler (source in `presql2-latest.zip`).
- `./comp-all-no-rdbms.sh`: COBOL-files-only build. It links `dummy-rdbmsMT.cbl` (stub DAL entry points) instead of the MySQL libs. Use this when MySQL isn't installed.
- `./comp-all-diags.sh` / `./comp-all-no-rdbms-diags.sh`: debug builds (`-d -g -ftraceall -fdump=ALL`).

To rebuild a single sub-system, `cd` into its directory and run its script, e.g. `cd sales && ./comp-sales-no-rdbms.sh`. There are also `comp-gl*.sh`, `comp-irs*.sh`, `comp-purchase*.sh`, `comp-stock*.sh` and `common/comp-common*.sh`.

To compile a single program, copy the matching line from the sub-system script. Typical forms:
```
cobc -m sl910.cbl dummy-rdbmsMT.cbl -I ../copybooks -Wlinkage -lz -D_FORTIFY_SOURCE=1          # no RDBMS
cobc -m sl910.cbl cobmysqlapi.o -I ../copybooks -Wlinkage -L/usr/local/mysql/lib -lmysqlclient -lz   # RDBMS
```
Sub-programs compile with `-m` (to `.so`). The menu drivers (`sales`, `purchase`, `stock`, `general`, `irs`, `ACAS`) and the `*LD`/`*UNL`/`*RES` utilities compile with `-x` (executables). `-T name.prn` produces listings. Copybooks resolve via `-I ../copybooks` / `COBCPY`.

`install-ACAS.sh` (first install) or `install-ACAS-preinstalled.sh` (later installs) moves the binaries into `~/bin`. The first-install script also appends env vars to `~/.bashrc`. At runtime, `ACAS_LEDGERS` (data directory, e.g. `~/ACAS`) and `ACAS_BIN` must be set, plus `COB_LIBRARY_PATH=~/bin`, `COB_SCREEN_ESC=YES`, `COB_SCREEN_EXCEPTIONS=YES`. The terminal must be at least 80x24.

There is no automated test suite. Testing is manual, done through the menus, using COBOL files rather than RDBMS (see `ACAS-Manuals/ACAS - Test Strategy`, `Test Standards`). `copybooks/Test-Data-Flags.cob` and the CDF constant in `common/fhlogger.cbl` control file-access logging.

## Architecture

**Layout**: `common/` holds shared modules, the file handlers and the DALs. `copybooks/` holds all shared COBOL copybooks. `irs/`, `general/`, `sales/`, `purchase/` and `stock/` each contain one sub-system. `mysql/ACASDB.sql` is the DB schema. `ACAS-Manuals/` holds the user and build docs (ODT/PDF). `Basic-Code/` contains unrelated legacy/experimental code (OE, Payroll) that is not part of the build.

**Program naming**: each sub-system has a menu driver (`sales.cbl`, `purchase.cbl`, `stock.cbl`, `general.cbl`, `irs.cbl`) and numbered programs with the prefixes `sl`, `pl`, `st`, `gl` and `irs`. The number groups by function: for example `sl9xx` is invoicing and `sl8xx` is recurring (autogen) invoices. Menu drivers `CALL` programs dynamically: `move "slNNN" to ws-called` → `call ws-called using ws-calling-data file-defs`. `ACAS.cbl` is the top-level menu across all sub-systems. `sys002` creates and maintains the system parameter file and runs automatically if that file is missing. `xl150` is shared by sales and purchase.

**Three-layer I/O (v3.02+)**. Application programs never do file I/O directly:
1. The application calls a **File Handler (FH)** `acasNNN` through paragraphs in `copybooks/Proc-ACAS-FH-Calls.cob`, e.g. `perform Sales-Read-Indexed`. The call passes `System-Record`, the WS record, `File-Access` (from `wsfnctn.cob`), `File-Defs` and `ACAS-DAL-Common-Data`. Set `File-Key-No` to pick the key, and check `fs-reply` after each call.
2. The FH number `NNN` matches the `file-NN` copybook that holds the filename, e.g. `file12.cob` = `salesled.dat` → `acas012`. The FH handles the COBOL file itself or, when the param file says RDBMS is in use, calls the matching **DAL**.
3. The **DAL** is `<name>MT.cbl` in `common/` (e.g. `salesMT`). It is **generated**: edit `<name>MT.scb` (EXEC SQL source), then `presql2` preprocesses it into `<name>MT.cbl`. Don't hand-edit `*MT.cbl`. DALs always read and write whole rows. `dummy-rdbmsMT.cbl` provides stub entry points for no-RDBMS builds; copies of it sit in each sub-system directory.

Per-table utilities in `common/`: `*LD` loads COBOL files into tables, `*UNL` unloads files to sequential (`.seq`), and `*RES` restores `.seq` to `.dat`. `masterLD.sh`, `masterUNL.sh` and `masterRES.sh` run them in bulk from the data directory.

**Key cross-cutting rule**: `acas012` + `salesMT` are the reference FH/DAL. If you fix a bug that isn't file-specific in any FH or DAL, apply the same fix to **all** the other FHs/DALs.

**Record layouts** live in copybooks, named by convention: `fdXXX.cob` (FD), `selXXX.cob` (SELECT), `wsXXX.cob` (working storage), with `sl`/`pl` prefixes for ledger-specific ones. `wssystem.cob` is the large system parameter record, and `wsfnctn.cob` holds the File-Access / FH function block. Changing a record layout means updating, together: the fd/ws copybooks, `mysql/ACASDB.sql`, the matching `*MT.scb`, `*LD` and `*UNL`/`*RES`, and, if existing data must change, an `acasconvert*` program.

## Conventions

- Sources are free-format (`>>source free` on line 1). A few files in `common/` are exceptions.
- Every program has a change log near the top of its source, in the form `*> dd/mm/yy vbc - .NN description`, and a version number. When you change a program, add an entry and bump its version. Each sub-system also has a `Changelog`, and the repo root has a system-level `Changelog` and `README` (newest entries first).
- User-facing messages are defined as numbered constants (e.g. `SL901`, `SY009`) in each program's working storage.
- Compiles use `-Wlinkage`, and some add `-Wno-goto-section`: GnuCOBOL 3.2 warns about `GO TO` the start of the same section, which is valid here.
- `accept_numeric.c` has been deliberately removed from the sales builds ("too many problems"). Don't re-add it.
- Current status per README: IRS, Stock and Sales are tested. Purchase Ledger is still in system testing. General Ledger hasn't been re-verified since the GnuCOBOL migration, and its posting logic needs to be brought in line with IRS.
