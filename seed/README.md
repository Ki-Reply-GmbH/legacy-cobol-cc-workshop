# ACAS start-up data

The first time ACAS starts it asks for its system parameters, saves them in `system.dat`, and then creates the default Sales and Purchase analysis records. The files in this folder are the result of that first start, so workshop participants don't have to go through the set-up screens. [`setup-acas.sh`](../setup-acas.sh) copies them into a fresh `~/ACAS`, and ACAS then opens straight on its main menu.

| File | What it holds | Format |
|---|---|---|
| `system.dat` | The system parameters (the answers below) | GnuCOBOL relative file, 4 records |
| `analysis.dat` | Default Sales and Purchase analysis codes (file 15) | GnuCOBOL indexed file (Berkeley DB 5.3, B-tree v9) |
| `value.dat` | The matching value records (file 13) | Same as `analysis.dat` |
| `SHA256SUMS` | Checksums of the three data files, written by `make-seed.py` | Text, `sha256sum -c` format |
| `make-seed.py` | Makes or checks these files by running the real ACAS screens | Python 3.8+, standard library only |

All three data files were written by ACAS itself (`sys002` and `sl070`), never edited by hand.

## How setup-acas.sh uses them

- **Only on a fresh install**: if `~/ACAS/system.dat` doesn't exist yet. Existing ACAS data is never overwritten, and `--clean` rebuilds keep it.
- **Tested first**, if `python3` is available. The script runs `make-seed.py --verify` against your new build, in a temporary folder. It checks that:
  - the files match `SHA256SUMS` byte for byte;
  - ACAS opens on its main menu;
  - Sales reads the analysis codes back from `analysis.dat` (menu **L**, option **5**);
  - every ledger opens and exits with status 0.

  If any check fails, the files are **not** installed and ACAS shows its normal set-up screens instead. That covers a damaged file, or a GnuCOBOL built with an indexed-file handler that can't read Berkeley DB files.
- **Without `python3`**, only the checksums are checked (`sha256sum`, or `shasum` on macOS).
- **Opt out** with `ACAS_NO_SEED=1 bash setup-acas.sh` to see ACAS's own set-up screens, for example to practise them or to enter your own company name (it can't be changed later).

## The answers

| Screen | Field | Value |
|---|---|---|
| 0 | Company name | `ACAS Workshop` |
| 0 | The six "Using …" questions (General, IRS, Purchase, Stock, Sales, Invoicing) | `Y` for all |
| 1 | Date format | `1` (UK, dd/mm/yyyy) |
| 1 | Financial year | `01/01/2026` to `31/12/2026`, statistics year 2026 |
| 1 | System print lines | `048` |
| 1 | VAT rates | ACAS's defaults: 20.00, 5.00, 0.00 |
| 1 | Data File Handling | `0` (COBOL files; the workshop build has no database) |
| 2 | Single/Multi-user | `0` (single) |
| 2 | Operating System | `6` (Linux) |
| 2 | Print spool names 1–3 | `none` (there's no printer; printing a report fails with "printer does not exist") |
| 4 | Use IRS instead of GL? | `Y` (IRS is the tested ledger; General Ledger hasn't been re-verified since the GnuCOBOL migration) |
| 5–8 | Sales, Purchase and Stock parameters | ACAS's defaults |
| 9 | IRS client name | `ACAS Workshop` |
| end | Do you want printed copy? | `N` |

Then the default analysis codes, created by Sales menu option **L** (`sl070`).

**macOS uses the same files.** Operating System `6` (Linux) is fine there: outside the set-up screens the programs only test whether the field is zero, and Sales treats Linux, Unix and Mac alike (the same backup script; `sales/sales.cbl:419-436`).

**The date ACAS offers.** `system.dat` stores the date ACAS last ran (11/10/2026, when these files were made). Sales offers that stored date at "Enter todays date", as it does after any earlier session. Type today's date if it matters.

**Changing settings later.** Press **Z** (System Setup) on the ACAS menu. Everything except the company name and the six sub-system questions can be changed there.

## Why the analysis files are included: an upstream bug

On a first launch, `common/ACAS.cbl` runs the set-up screens and then, at lines 412–413, creates the default analysis records:

```cobol
move     "sl070" to ws-called
call     ws-called using ws-calling-data file-defs
```

But `sl070` takes four arguments (`sales/sl070.cbl:276-279`: `ws-calling-data system-record to-day file-defs`), and every other caller passes all four, for example the Sales menu (`sales/sales.cbl:683-686`) and `sl055`, `sl910`, `pl030`, `pl055`. With only two, `sl070` reads `file-defs` where it expects the system record and finds no `to-day` at all. A normal build crashes with a segmentation fault right after the last set-up screen, whatever you answer to "printed copy". A build with runtime checks (`cobc -d`) reports it exactly:

```
libcob: sl070.cbl:278: error: LINKAGE item to-day not passed by caller
```

The settings are already saved by then, so the second start works. But it skips this block, so the analysis records are never created that way. `make-seed.py` creates them the way the Sales menu does (option **L**), which is what the first launch was meant to do. The COBOL is unchanged. A fix belongs upstream: pass the same four arguments as `sales/sales.cbl:683-686`, after reading the system record (it is read just after this block).

## Regenerating the files

Do this when the financial year should change, after a change to the record layout of the system, analysis or value files (`copybooks/wssystem.cob`, `fdanal.cob`, `fdval.cob`, ...), or for a GnuCOBOL built with a different indexed-file handler.

1. Install ACAS with `bash setup-acas.sh` and open a new terminal, so `ACAS` is on `PATH` and `COB_LIBRARY_PATH` is set.
2. From the repository root, in WSL, Linux or macOS:
   ```bash
   python3 seed/make-seed.py                # or: --company "Name" --year 2027
   python3 seed/make-seed.py --verify       # ACAS must open on its menu; Sales and every ledger must open and exit cleanly
   ```
   Both work in a temporary folder, so your own `~/ACAS` isn't touched. `--debug` prints every screen and the keys sent to it, which is the first thing to look at if a screen changed.
3. If you changed the company name or year, update the table above, and the messages in `setup-acas.sh` that name them.
4. Commit all four data files together (`system.dat`, `analysis.dat`, `value.dat`, `SHA256SUMS`).

Regenerating with the same answers gives a byte-identical `system.dat`. `analysis.dat` and `value.dat` differ in 8 bytes of their Berkeley DB header (offsets 53–66, the unique file ID every new database gets); their records are the same. That's why `SHA256SUMS` is rewritten on every run.

`make-seed.py` drives ACAS through a pseudo-terminal with a small built-in terminal emulator, so it needs no extra packages. `.gitattributes` marks `*.dat` as binary, so git never changes their bytes, even with `core.autocrlf=true` on Windows. `.gitignore` ignores `*.dat` everywhere except this folder.
