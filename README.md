# Oracle Dump Archiver

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passed-brightgreen)](https://shellcheck.net)

A robust Bash script that automatically groups and compresses Oracle Data Pump (expdp) `.dump` files by date, producing daily `.tar.gz` archives. Designed for large files (GB to tens of GB) and cron‑based automation.

## 📦 Overview

Oracle Data Pump exports frequently generate many `.dump` files across different dates. This script:

1. Scans specified source directories for `.dump` files.
2. Extracts the date (`YYYYMMDD`) from the filename (pattern `*_YYYYMMDD*.dump`).
3. Moves files belonging to the same date into a temporary working directory (parallel moves with configurable concurrency).
4. Creates a tar archive and compresses it with `gzip` (`tar | gzip`).
5. Stores the final archive as `YYYYMMDD.tar.gz` in a backup directory.
6. Cleans up temporary files – ready for cron.

## ✨ Features

- **Date‑based grouping** – works with typical expdp naming like `RB.EVENT_USAGE_2747_20260330150406.dump`
- **Efficient for large files** – streaming compression (`tar … | gzip`) avoids intermediate large files
- **Parallel file moves** – configurable concurrency to speed up the staging phase
- **Cron‑ready** – runs once, then exits; perfect for hourly/daily scheduling
- **Safe** – uses `find` with `-maxdepth 1` and checks for existing archives to avoid double processing
- **Logging** – all actions timestamped to a log file

## 📋 Prerequisites

- **Bash** 4.0+
- **GNU tar** and **gzip** (usually pre‑installed on Linux)
- A user account with **read** access to source directories and **write** access to backup and temp directories
- **date** command that supports `--date` (GNU date) – works on most Linux distributions

## 🚀 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/oracle-dump-archiver.git
   cd oracle-dump-archiver
   ```
   
2. Make the script executable:
   ```bash
   chmod +x compress_dump.sh
   ```

3. Edit configuration variables inside compress_dump.sh (see Configuration).

4. Test run manually:
   ```bash
   ./compress_dump.sh
   ```
