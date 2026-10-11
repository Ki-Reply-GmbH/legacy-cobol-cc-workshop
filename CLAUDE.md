# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ACAS (Applewood Computers Accounting System) v3.3 — a GnuCOBOL (3.2) accounting suite, maintained by Vincent B. Coen. Sub-systems: IRS (incomplete-records bookkeeping), General Ledger, Sales Ledger, Purchase Ledger, Stock Control. Data is stored either in COBOL ISAM/flat files or in MySQL/MariaDB (the only RDBMS supported), selected at runtime by the system parameter file.

The build and runtime target is Linux with bash. This checkout is on Windows, so the `.sh` build scripts won't run here unless GnuCOBOL (`cobc`) is available, for example via WSL (this machine's WSL Ubuntu has GnuCOBOL 3.2.0 at `/usr/bin/cobc`). The directory is a local git repo with a single import commit, so there's no upstream history. Upstream uses SourceForge SVN/CVS. `.gitignore` excludes `ACAS-Manuals/`, `Basic-Code/`, `home/` and `etc/`, so those exist on disk but aren't tracked.

## Build

Run the top-level scripts from the repo root. Each one `cd`s into each sub-system directory and runs that directory's script:

- `./comp-all.sh`: full build with RDBMS. Needs the MySQL/MariaDB client libs at `/usr/local/mysql/lib`, `cobmysqlapi.o`, and the `presql2` precompiler (source in `presql2-latest.zip`).
- `./comp-all-no-rdbms.sh`: COBOL-files-only build. It links `dummy-rdbmsMT.cbl` (stub DAL entry points) instead of the MySQL libs. **It is broken as shipped**: it calls `common/comp-common-no-rdbms.sh`, which doesn't exist. Use `setup-acas.sh`, which patches this, or `comp-all-no-rdbms-diags.sh`. See the build-script reference below.
- `./comp-all-diags.sh` / `./comp-all-no-rdbms-diags.sh`: debug builds (`-d -g -ftraceall -fdump=ALL`).

To rebuild a single sub-system, `cd` into its directory and run its script, e.g. `cd sales && ./comp-sales-no-rdbms.sh`. There are also `comp-gl*.sh`, `comp-irs*.sh`, `comp-purchase*.sh`, `comp-stock*.sh` and `common/comp-common*.sh`.

To compile a single program, copy the matching line from the sub-system script. Typical forms:
```
cobc -m sl910.cbl dummy-rdbmsMT.cbl -I ../copybooks -Wlinkage -lz -D_FORTIFY_SOURCE=1          # no RDBMS
cobc -m sl910.cbl cobmysqlapi.o -I ../copybooks -Wlinkage -L/usr/local/mysql/lib -lmysqlclient -lz   # RDBMS
```
Sub-programs compile with `-m` (to `.so`). The menu drivers (`sales`, `purchase`, `stock`, `general`, `irs`, `ACAS`) and the `*LD`/`*UNL`/`*RES` utilities compile with `-x` (executables). `-T name.prn` produces listings. Copybooks resolve via `-I ../copybooks` / `COBCPY`.

**Start-up data (`seed/`, not upstream).** `seed/system.dat`, `analysis.dat` and `value.dat` hold what a first ACAS launch creates: the system parameters for company "ACAS Workshop", financial year 2026, plus the default analysis codes. ACAS itself wrote them, driven by `seed/make-seed.py`. `setup-acas.sh` installs them into a fresh `~/ACAS` (never over existing data; `ACAS_NO_SEED=1` skips them), so ACAS opens on its main menu. Answers, regeneration and checks are in `seed/README.md`. `.gitignore` excludes `*.dat` except `seed/`, and `.gitattributes` marks `*.dat` binary. Known upstream bug the seed avoids: `common/ACAS.cbl:412-413` calls `sl070` with two of the four arguments it declares (`sales/sl070.cbl:276-279`), so an unseeded first launch crashes right after the set-up screens.

`install-ACAS.sh` (first install) or `install-ACAS-preinstalled.sh` (later installs) moves the binaries into `~/bin`. The first-install script also appends env vars to `~/.bashrc`. At runtime, `ACAS_LEDGERS` (data directory, e.g. `~/ACAS`) and `ACAS_BIN` must be set, plus `COB_LIBRARY_PATH=~/bin`, `COB_SCREEN_ESC=YES`, `COB_SCREEN_EXCEPTIONS=YES`. The terminal must be at least 80x24.

There is no automated test suite. Testing is manual, done through the menus, using COBOL files rather than RDBMS (see `ACAS-Manuals/ACAS - Test Strategy`, `Test Standards`). `copybooks/Test-Data-Flags.cob` and the CDF constant in `common/fhlogger.cbl` control file-access logging.

## Architecture

**Layout**: `common/` holds shared modules, the file handlers and the DALs. `copybooks/` holds all shared COBOL copybooks. `irs/`, `general/`, `sales/`, `purchase/` and `stock/` each contain one sub-system. `mysql/ACASDB.sql` is the DB schema. `ACAS-Manuals/` holds the user and build docs (ODT/PDF). `Basic-Code/` contains unrelated legacy/experimental code (OE, Payroll) that is not part of the build.

**Program naming**: each sub-system has a menu driver (`sales.cbl`, `purchase.cbl`, `stock.cbl`, `general.cbl`, `irs.cbl`) and numbered programs with the prefixes `sl`, `pl`, `st`, `gl` and `irs`. The number groups by function: for example `sl9xx` is invoicing and `sl8xx` is recurring (autogen) invoices. Menu drivers `CALL` programs dynamically: `move "slNNN" to ws-called` → `call ws-called using ws-calling-data file-defs`. `ACAS.cbl` is the top-level menu across all sub-systems. `sys002` creates and maintains the system parameter file and runs automatically if that file is missing. `xl150` is shared by sales and purchase.

**Three-layer I/O (v3.02+)**. Application programs do all ledger/master-file I/O through this layer. A few files bypass it: the BO item file, work/sort/temp files, and archive/cheque files (see "Files with no FH/DAL" below).
1. The application calls a **File Handler (FH)** `acasNNN` through paragraphs in `copybooks/Proc-ACAS-FH-Calls.cob`, e.g. `perform Sales-Read-Indexed`. The call passes `System-Record`, the WS record, `File-Access` (from `wsfnctn.cob`), `File-Defs` and `ACAS-DAL-Common-Data`. Set `File-Key-No` to pick the key, and check `fs-reply` after each call.
2. The FH number `NNN` matches the `file-NN` copybook that holds the filename, e.g. `file12.cob` = `salesled.dat` → `acas012`. The FH handles the COBOL file itself or, when the param file says RDBMS is in use, calls the matching **DAL**.
3. The **DAL** is `<name>MT.cbl` in `common/` (e.g. `salesMT`). It is **generated**: edit `<name>MT.scb` (COBOL with presql2 `/MYSQL …\` directives, not `EXEC SQL`), then `presql2` preprocesses it into `<name>MT.cbl`. Don't hand-edit `*MT.cbl`. DALs always read and write whole rows. `dummy-rdbmsMT.cbl` provides stub entry points for no-RDBMS builds; copies of it sit in each sub-system directory.

Per-table utilities in `common/`: `*LD` loads COBOL files into tables, `*UNL` unloads files to sequential (`.seq`), and `*RES` restores `.seq` to `.dat`. `masterLD.sh`, `masterUNL.sh` and `masterRES.sh` run them in bulk from the data directory.

**Key cross-cutting rule**: `acas012` + `salesMT` are the reference FH/DAL. If you fix a bug that isn't file-specific in any FH or DAL, apply the same fix to **all** the other FHs/DALs.

**Record layouts** live in copybooks, named by convention: `fdXXX.cob` (FD), `selXXX.cob` (SELECT), `wsXXX.cob` (working storage), with `sl`/`pl` prefixes for ledger-specific ones. `wssystem.cob` is the large system parameter record, and `wsfnctn.cob` holds the File-Access / FH function block. Changing a record layout means updating, together: the fd/ws copybooks, `mysql/ACASDB.sql`, the matching `*MT.scb`, `*LD` and `*UNL`/`*RES`, and, if existing data must change, an `acasconvert*` program.

## Conventions

- Sources are free-format (`>>source free` on line 1). A few files in `common/` are exceptions.
- Every program has a change log near the top of its source, in the form `*> dd/mm/yy vbc - .NN description`, and a version number. When you change a program, add an entry and bump its version. Each sub-system also has a `Changelog`, and the repo root has a system-level `Changelog` and `README` (newest entries first).
- User-facing messages are defined as numbered constants (e.g. `SL901`, `SY009`) in each program's working storage.
- Compiles use `-Wlinkage`. `-Wno-goto-section` is mentioned only in script comments and no active `cobc` line passes it, so expect GnuCOBOL 3.2's warnings about `GO TO` the start of the same section. They're harmless: the code is valid.
- `accept_numeric.c` has been deliberately removed from the sales builds ("too many problems"). Don't re-add it.
- Current status per README: IRS, Stock and Sales are tested. Purchase Ledger is still in system testing. General Ledger hasn't been re-verified since the GnuCOBOL migration, and its posting logic needs to be brought in line with IRS.

## v3.3 architecture notes

Findings from reading this checkout on 2026-09-25. Evidence is cited as file paths. Where a file named in the original investigation brief doesn't exist, that is stated explicitly rather than guessed at.

### Named in the brief but not in this checkout

I searched the whole tree case-insensitively and listed the contents of every archive (`presql2-latest.zip`, the `Basic-Code/*.zip` files, and both connector source archives). None of these exist anywhere:

| Asked for | What exists instead |
|---|---|
| `1-README.TXT`, `README.OE`, top-level `TODO` | `README` (byte-identical to `README.TXT`), `README.nightly`, `README.SVN` (one line: "See the file README."). The only TODO files are `common/TODO`, `stock/TODO` and `irs/TODO-Programming.txt`. OE is covered inside `README` (2024-04-16 and 2024-12-22 entries). |
| `cobol-sources.txt` (manifest) | None. The inventory below comes from `git ls-files` plus glob. |
| `copybooks-2/` | None. `copybooks/` is the only copybook directory (see below). |
| `JCs-mysql-preprocessor/`, `ACASDB-msql-2-mysql-v2.sql` | The precompiler ships as `presql2-latest.zip`, and the schema is `mysql/ACASDB.sql`. |
| `Experimental-Stuff/` | None. |
| `payroll/` (top level) | Only `Basic-Code/Payroll/`, which is CBASIC, not COBOL. |
| `cntlines.cob` | None. There's no line-counting utility in the tree or the archives. LOC figures below come from a stated substitute method. |
| `bcscr`, `bcscr.c` | None. The only C source is `common/accept_numeric.c` (see "C helpers" below). |
| SVN log | Not available. `git log` has a single import commit (`d8dc6e0`). |

### Release summary

- **What it is**: v3.3 "pre-final release" (README 2025-09-21; root `Changelog` 2025-09-20 "3.3.00 Version update and builds reset"). v3.3 supersedes v3.2, and fixes are back-ported to v3.2 "as time allows".
- **Stable** (README 2025-09-21): "all testing is complete for IRS, Stock and Sales apart for some reports".
- **In progress**: Purchase Ledger system testing ("hopefully concluding before the end of year"). General Ledger hasn't been touched since the GnuCOBOL migration, and its posting and year-end retention logic needs aligning with IRS. Back Orders (BO): basic testing done 2025-04-14 (`st020`, `sl970`, `sl910`), but `sl970` amendments have had "very limited testing". Recurring invoices (autogen, `sl8xx`): coded, "needs testing". `masterLD.sh`/`masterRES.sh`: "so far only tested masterUNL" (root `Changelog` 2025-03-07).
- **Post-3.3.00 changes**: 3.3.01 (2025-10-05) changed `sl060`/`sl100` and `pl060`/`pl100` "BL-close for GL & IRS. But need to check with GL if posting will work" (`sales/Changelog`, `purchase/Changelog`).
- **Terminated or abandoned**: OE (Order Entry) GnuCOBOL port stopped 2024-12-22 once BO was added to ACAS. It was distributed separately as `OE-nightly.rar` and is not in this tree. There is no Payroll in ACAS. The UK rewrite was never open-sourced (`Basic-Code/README.TXT`).
- **Stale TODOs**: `common/TODO` says "25/10/02 - Nothing.". `stock/TODO` dates from 2009, and its item 5 says "LOOKS DONE - NEED TO RECHECK". `irs/TODO-Programming.txt` says "None, All completed ... Verified 25/06/2023".

### Module maturity

| Module | Status | Evidence |
|---|---|---|
| `irs/` | **Stable** | README 2025-09-21: testing complete. `irs/TODO-Programming.txt`: "All completed", verified 2023-06-25. Last functional change 2024-01-05 (`irs/Changelog`). Uses its own FH family `acasirsub1/3/4/5` → `irs*MT` DALs (13 of 16 programs). |
| `stock/` | **Stable** | README 2025-09-21: testing complete. BO changes to `st020` tested 2025-04-14. `stock/TODO` is 2009-era and stale. |
| `sales/` | **Stable core, active edges** | Core tested (README). Two areas are still active. BO (`sl910`, `sl970`) has limited testing of `sl970` amendments. Autogen `sl800`→`sl810/820/830` is fully wired from `sl900`, but the root Changelog (2025-03-07) says "Still to do - sl800 series". 3.3.01 `sl060`/`sl100` GL posting is unverified. |
| `purchase/` | **Active development (system testing)** | README 2025-09-21: "still undergoing system testing". `pl020` bug fixes 2025-08-19, and 3.3.01 changes as above. Autogen is only a shell: `pl180` calls `pl800` (a 251-line menu), whose calls to `pl810/820/830` are commented out, and those programs don't exist. |
| `general/` | **Unverified since migration; needs rework** | README 2025-09-21: not worked on since the GnuCOBOL migration, and posting logic must be brought in line with IRS. Last change was cosmetic (2023-06-05, print sizes). |
| `common/` | **Active (shared infrastructure)** | FHs, DALs, `sys002`, `xl150`, `ACAS.cbl`, the load/unload/restore utilities. `*RES` fixed 2025-03-23. `masterLD`/`masterRES` untested. |
| MySQL/MariaDB path | **Implemented, secondary** | Complete DAL coverage for 32 tables, but the manual test strategy uses COBOL files, and an RDBMS build can't succeed from this tree alone (see below). |
| `Basic-Code/` (OE, Payroll, IY, NAD) | **Legacy, not part of the system** | Entirely CBASIC for CP/M/MP/M, about 1979–81. It contains no COBOL, and no build script references it. `.gitignore` excludes it. Each `*.zip` mirrors its directory. It's kept "for your interest", with advice on porting it to FreeBASIC or COBOL (`Basic-Code/README.TXT`). |
| `Experimental-Stuff/`, `payroll/` | **Absent** | See the table above. The `OE`, `payroll` and `epos` blocks in `comp-all*.sh` are commented out: "Not yet released under Open Source". |

**Assumption check.** "`Basic-Code/` is legacy or superseded": confirmed. More precisely, it is ancestral 1979–81 CBASIC. IY was the predecessor of `stock/`, but the COBOL Stock Control "made use of very few of the design elements". OE's one unique feature, BO, was reimplemented in `sales/` and `stock/`. NAD and Payroll have no ACAS COBOL counterpart. It isn't scratch work. `Experimental-Stuff/` can't be assessed because it doesn't exist.

**Payroll (`Basic-Code/Payroll/`).** It's a US-market CBASIC system: 152 `.bas` files (73 in `src/`, of which 36 are `fpy*` screen definitions, plus 79 under `src/includes/`), dated Dec 1979 to Jan 1980. The only README note on its state says it "has NOT been updated since around 1980/1". The October 2025 notes add that the file names were lowercased, drive letters were removed from includes "but I know I have missed many", and the code hasn't been through a compiler. Read as a code base, it looks complete for its era:
- `py.bas` (the menu) lists 25 modules. Across all programs, the `chain` / `module$()` references name 34 distinct targets.
- 33 of those targets have source. The 34th, `pyhours`, is a menu slot with `exception%(03)=1`, and `pysrtprm.bas` builds a `PYHOURS.SRT` sort file for it. So it's a sort step, not a missing program.
- `prnt941b` is reached as `SECTION2$` of `print941`. `pypar2`/`pypar3` belong to the parameter-entry set (`pyparent`, `fpypar2/3`).
- The 36 small `fpy*.bas` files (39–75 lines) are screen-form definitions ("PAYROLL SYSTEM SCREEN FILES, JANUARY 21, 1980"), not stubs.
- The only explicit gap marker is `hisprint.bas:213` ("print coh info (not implemented yet)").

Nothing is compilable with this toolchain, it has no ACAS integration, and the manual is "Provisional".

### copybooks/ (there is no copybooks-2/)

There is exactly one copybook directory, `copybooks/`, with 156 tracked files. It's used everywhere: every build script sets `COBCPY=../copybooks` and passes `-I ../copybooks`, and no `COPY` statement uses a path. There's no copybook variant or split for agents to choose between.

Some `COPY` targets don't resolve from `copybooks/`:
- `screenio.cpy` comes from GnuCOBOL's own copy directory (`/usr/share/gnucobol/copy/`), which is fine. It's used far more broadly than any one module: `common/sys002.cbl`, all of `irs/`, `general/`, most of `purchase/` and `sales/`, and `stock/st010`/`st020`/`st030` — 39 files tree-wide as of this check (`grep -rl 'copy "screenio.cpy"'`). An earlier version of this file said it was used only by `sys002`, `irs.cbl` and `general/`; that undercounted it substantially and has been corrected.
- **`ACAS-SQLstate-error-list.cob` is missing from the tree.** 22 of the 28 `*MT.scb`/`*MT.cbl` DALs `COPY` it (around line 160). The reference DAL `salesMT` is one of the six that don't. An RDBMS build fails on those 22 DALs until the copybook is supplied.
- **`slfdinv2.cob` is missing.** Only `common/acasconvert3.cbl` uses it, and no script compiles that program.
- `common/ACCEPTNM.CPY` sits outside `copybooks/`. It pairs with `accept_numeric.c` and is now unused.

### MySQL/MariaDB architecture

It's a **source-to-source precompiler feeding a separate set of data-access programs (DALs)**, selected at runtime per call. There's no runtime SQL substitution layer. The pieces:

1. **Runtime switch**: `System-Record` → `RDBMS-Flat-Statuses` → `File-System-Used` (`copybooks/wssystem.cob:110`): 0 = COBOL files, 1 = MySQL/MariaDB. The other RDBMS values are commented out. Every FH checks it on every call, e.g. `common/acas012.cbl:316`: `if not FS-Cobol-Files-Used … perform ba-Process-RDBMS`, which does `call "salesMT"`. The old dual-write mode (`File-Duplicates-In-Use`) is marked "No longer in use".
2. **DAL source** is `common/<name>MT.scb`: ordinary free-format COBOL with presql2 directive blocks `/MYSQL VAR|INIT|PRO|SELECT|FETCH|INSERT|UPDATE|DELETE|FREE|CLOSE\ … /MYSQL-END\`. This is JC's presql2 syntax, not `EXEC SQL`. The comments in the FHs and DALs that mention "EXEC SQL" and per-RDB directories (MSSQL, DB2, Oracle, and so on) describe plans that were never built.
3. **presql2** (`presql2-latest.zip` → `presql2-package/presql2.cbl`, itself COBOL) rewrites each directive into commented-out originals plus generated code. That code is a `COPY "mysql-variables.cpy"`, a host-variable record (`TD-<TABLE>` with `HV-*` fields), and `PERFORM MYSQL-nnnn` paragraphs from `copybooks/mysql-procedures.cpy`. For `salesMT` this turns 1,093 lines into 2,269. **presql2 reads column definitions from a live server's `information_schema`**: `presql2.param` holds `DBHOST`, `DBUSER`, `DBPASSWD`, `DBNAME=information_schema` and port/socket. So regenerating DALs needs a running MySQL/MariaDB with `ACASDB` loaded from `mysql/ACASDB.sql`. There are separate MariaDB and MySQL variants (`Variations/presql2M.cbl`, `presql2o.cbl`) because MariaDB's `information_schema` has one extra column.
4. **C bridge**: the generated paragraphs `CALL "MySQL_init"`, `"MySQL_real_connect"`, `"MySQL_query"`, `"MySQL_fetch_record"`, `"MySQL_errno"`, `"MySQL_sqlstate"` and others. These live in `cobmysqlapi.o`, built from `presql2-package/cobmysqlapi38.c` with `gcc -I/usr/local/mysql/include -c cobmysqlapi38.c -o cobmysqlapi.o -fPIC`, and linked with `-lmysqlclient`. **`cobmysqlapi.o` is not in the tree.** You must build it from the zip.
5. **No-RDBMS stub**: `dummy-rdbmsMT.cbl` defines all 28 DAL entry points as one section that sets `FS-Reply 99`, `WE-Error 999`, `RETURN-CODE 64` and `goback`. So a no-RDBMS build that finds `File-System-Used = 1` fails every file call; it doesn't fall back to COBOL files. The five sub-system copies are byte-identical to `common/dummy-rdbmsMT.cbl`.
6. **Coverage**: `mysql/ACASDB.sql` is a MariaDB 10.11.7 dump (config 30/03/2024) with 33 `CREATE TABLE`s, no data. The 28 DALs use 32 of them. The 33rd, `PLPAY-RECrg01`, has no DAL referencing it. Migration tooling: `*LD` (file → table, linked with MySQL) and `*UNL`/`*RES` (file ↔ `.seq`, pure COBOL).

**Which modules use it**: every module in the build, and none of them directly. All SQL is confined to `common/*MT`. Sub-systems reach it only through the FHs: IRS through `acasirsub1/3/4/5` (13 of 16 programs), and General, Sales, Purchase and Stock through `Proc-ACAS-FH-Calls.cob` / `acas0NN` (13 of 18, 33 of 37, 32 of 38 and 7 of 9 programs). There is no `payroll/` module. Everything in `Basic-Code/` uses native CBASIC files only.

**Files with no FH/DAL, which stay COBOL files even in RDBMS mode**: `bostkitm.dat` (file-31, BO items, used directly by `sl010`, `sl910` ("NOT using FH"), `sl970` and `st020`), `archive.dat` (file-02, GL `gl080`/`gl100`/`gl105`), `cheque.dat` (file-33, `pl940`/`pl960`), the IRS `Saved-CoA` archive, and the work/sort/temp files (`work.tmp`, `oisort.wrk`, `poisort.wrk`, `openitm2.dat`, `openitm4.dat`, `tmp-stock.dat`, `pretrans.tmp`/`postrans.tmp`, `postsort.dat`).

### Build-script reference

There's no dialect flag: no script passes `-std=`, so everything uses GnuCOBOL's default dialect. Free format is declared per source with `>>source free`. The only exceptions are two unbuilt files, `common/makesqltable-original.cbl` and `common/send-mail-test-example.cbl`. Sub-programs build with `-m`, and executables (menus, `ACAS`, `*LD`/`*UNL`/`*RES`) with `-x`. The top-level scripts only export `COBCPY` and `cd` into `common`, `general`, `irs`, `purchase`, `sales` and `stock` in that order. All the flags live in the sub-system scripts.

| Script | Builds | Flags | Needs MySQL/MariaDB? | Use when |
|---|---|---|---|---|
| `comp-all.sh` | All six dirs via `comp-common.sh`, `comp-gl.sh`, `comp-irs.sh`, `comp-purchase.sh`, `comp-sales.sh`, `comp-stock.sh`. Runs `presql2` on every `*MT.scb`, then compiles DALs, FHs, `maps0*`, `sys002`, `xl150`, `ACAS`, `*LD`, `*UNL`, `*RES` and all ledger programs. | `-Wlinkage`, `cobmysqlapi.o -L/usr/local/mysql/lib -lmysqlclient -lz`. GL/IRS/PL/stock add `-D_FORTIFY_SOURCE=1`. GL/IRS/PL add `-fdump=ws -fmissing-statement=ok`. Listings via `-T` in `common`. | **Yes, at build time**: client libs in `/usr/local/mysql/lib`, `presql2` on PATH, a live server for `presql2`, `cobmysqlapi.o` in each dir, ncursesw dev headers (it still compiles `accept_numeric.c`), and the missing `ACAS-SQLstate-error-list.cob`. Not runnable from this tree as-is. | Building a MySQL/MariaDB-capable release. The binaries also run on COBOL files if `File-System-Used = 0`. |
| `comp-all-diags.sh` | Same as `comp-all.sh`, via `*-diags.sh`. | Adds `-d -g -ftraceall -fdump=ALL`. `comp-common-diags.sh` compiles `ACAS-Sysout` twice. | Yes, same prerequisites. | Debugging an RDBMS-backed (DAL) program. |
| `comp-all-no-rdbms.sh` | All six dirs, no SQL. Stubs via `dummy-rdbmsMT.cbl`. | `-Wlinkage -lz`, sales adds `-D_FORTIFY_SOURCE=1`. | No. | **Broken as shipped.** It calls `common/comp-common-no-rdbms.sh`, which doesn't exist. The closest file, `comp-common-No-rdbms.sh`, is marked "DO NOT USE" by its author and compiles a nonexistent `dummy-rdbms.cbl`. `setup-acas.sh` writes a corrected script into a separate build copy. |
| `comp-all-no-rdbms-diags.sh` | All six dirs, no SQL, and copies `dummy-rdbmsMT.*` into each sub-system dir. | `-Wlinkage -lz -d -g -ftraceall -fdump=ALL`. `accept_numeric.c` and `*LD` are commented out. | No. | **The working choice for native-file testing** (debug build). Needs only `cobc` and zlib dev. |
| `setup-acas.sh` (not upstream) | Copies the tree to `~/cobolsrc/ACAS`, fixes the script above, strips CRLF, then runs `comp-all-no-rdbms.sh` and installs. On a fresh install it then copies the start-up data in `seed/` into `~/ACAS`, after `seed/make-seed.py --verify` passes against the new build. | As `comp-all-no-rdbms.sh`. | No. | A first release-style no-RDBMS build on WSL or Linux. |
| Sub-system scripts `<dir>/comp-<name>[-no-rdbms][-diags].sh` | One module: the menu driver (`-x` and `-m`) plus its `sl*`, `pl*`, `st*`, `gl*` or `irs0*`/`irsubp` programs. | Same as the matching top-level variant. | Only the non-`no-rdbms` ones. | Rebuilding one module after `common/` is built. **`sales/comp-sales-no-rdbms.sh` doesn't build the `sales` executable**: its `-x` line is commented out and it builds only `sales.so`. In a no-RDBMS build, Sales is reachable only from the `ACAS` menu. That was confirmed in the earlier WSL install, where `~/bin` has `sales.so` but no `sales`. |
| `common/` extras | `comp-common-debug.sh`, `comp-common-diags-trace.sh` (RDBMS + debug variants), `comp-common-with-cobxref.sh` (also runs `cobxref` cross-reference), `comp-common2.sh` (RDBMS without `presql2` regeneration), `comp-common-No-rdbms.sh` (broken, see above). `sales/comp-sales-and-prn.sh` and `irs/comp-irs-diags-trace.sh` are RDBMS variants too. | | All except `comp-common-No-rdbms.sh`. | Rarely. |

**Rule of thumb**: to test a native-file program, use `comp-all-no-rdbms-diags.sh` (or `setup-acas.sh`), then rebuild with `<dir>/comp-<name>-no-rdbms[-diags].sh`. To test a MySQL/MariaDB-backed program, use `comp-all-diags.sh`, but only after installing the client libs, building `cobmysqlapi.o` and `presql2` from the zip, loading `mysql/ACASDB.sql` into a running server, configuring `presql2.param`, and supplying `ACAS-SQLstate-error-list.cob`. Then set `File-System-Used = 1` in `sys002`.

### C helpers (the brief asked about bcscr)

There's no `bcscr` in the tree. The only C source is `common/accept_numeric.c` (v1.04, 2024-03-13, "Chuck H."). It's a libcob + ncursesw numeric-field `ACCEPT` routine called through `ACCEPTNM.CPY`, not a standalone utility. Its only user, `sl970`, removed it on 29/07/25 ("cannot build it without…"). `comp-common.sh` and `comp-common-diags.sh` still compile it, and install scripts copy it if present. `cobmysqlapi38.c`, inside the presql2 zip, is the other C component (MySQL bridge, above).

### Lines of code per module

`cntlines.cob` doesn't exist, so I counted with a substitute: an awk classifier run over tracked sources (2026-09-25). A comment is a free-format `*>` line, or a fixed-format column-7 `*` or `/` line. Blank lines are counted separately. Inline trailing `*>` comments count as code. Each sub-system figure includes its identical 174-line `dummy-rdbmsMT.cbl` copy. Generated DALs are shown separately so they aren't double-counted against their `.scb` source.

| Module | Files | Total lines | Code | Comment | Blank |
|---|---:|---:|---:|---:|---:|
| `sales/` (`*.cbl`) | 37 | 34,217 | 21,437 | 12,747 | 33 |
| `purchase/` (`*.cbl`) | 38 | 26,664 | 16,519 | 10,127 | 18 |
| `general/` (`*.cbl`) | 18 | 13,358 | 8,127 | 5,219 | 12 |
| `irs/` (`*.cbl`) | 16 | 12,410 | 7,764 | 4,639 | 7 |
| `stock/` (`*.cbl`) | 9 | 10,041 | 6,685 | 3,343 | 13 |
| `common/` hand-written `*.cbl` | 128 | 54,347 | 29,898 | 24,263 | 186 |
| `common/` DAL sources `*MT.scb` | 28 | 31,238 | 18,936 | 12,266 | 36 |
| `common/` generated `*MT.cbl` | 28 | 53,943 | 37,964 | 15,882 | 97 |
| `copybooks/` (`*.cob`, `*.cpy`) | 154 | 6,383 | 4,230 | 2,144 | 9 |
| `payroll/` | 0 | (no such module) | | | |
| `Basic-Code/Payroll/` (CBASIC `*.bas`, `rem` = comment) | 152 | 29,057 | 20,291 | 4,957 | 3,809 |

For reference, the other CBASIC trees: `Order_Entry` 3,980 lines, `iy` 8,288, `nad` 2,838.

### Couldn't determine; needs a human

1. **Whether the brief's missing files exist elsewhere**: `cntlines.cob`, `bcscr.c`, `copybooks-2/`, `JCs-mysql-preprocessor/`, `ACASDB-msql-2-mysql-v2.sql`, `cobol-sources.txt`, `Experimental-Stuff/`, `payroll/`. They may come from another ACAS release or archive (e.g. the SourceForge nightly or v3.2 tarballs). If they matter, point me at that source.
2. **Where `ACAS-SQLstate-error-list.cob` and `slfdinv2.cob` came from.** Were they left out of the upstream archive, or generated by something not included? Until one is supplied, 22 DALs won't compile.
3. **Whether the RDBMS build works at all with 3.3's presql2**: the zip's ACAS sample files date from 2018 and the precompiler from 2019. There's no MySQL on this machine, so I couldn't test it.
4. ~~Whether `setup-acas.sh`'s post-build check passes~~ **Resolved 2026-10-04.** The check had wrongly required `sales/sales`. It now checks `sales/sales.so` (the only Sales artifact the no-RDBMS script builds). A full run in WSL Ubuntu 26.04 (GnuCOBOL 3.2.0), with a simulated macOS install path, built with zero errors and launched the SYS002 setup screen.
5. **Actual runtime maturity**: I read the READMEs and Changelogs but ran no menus. Only the author's manual tests back the "Stable" labels. General Ledger's posting correctness is the biggest unknown.
6. **Purchase autogen intent**: README 2024-04-16 says "the need for it here is undetermined. Options?". Whether `pl810`–`pl830` should ever exist is the maintainer's call.
7. **Payroll completeness**: the assessment above comes from structure and chain targets only. Nothing has been compiled, since no CBASIC or FreeBASIC toolchain is present.
8. **Why `-Wno-goto-section` appears only in comments**: the 2022-12-08 README says it was added to the scripts, but no active command line has it. It may have been lost when the scripts were regenerated.
