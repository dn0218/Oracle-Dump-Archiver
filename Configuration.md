# ⚙️ Configuration

## Open `compress_dump.sh` and adjust these variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `SOURCE_DIRS` | Array of directories containing `.dump` files | `("/oracle/target" "/data/expdp")` |
| `BACKUP_DIR` | Destination directory for `.tar.gz` archives | `"/oracle/backup/dump_archives"` |
| `TEMP_WORK_ROOT` | Temporary workspace (needs free space for moved files) | `"/tmp/dump_compress_work"` |
| `ARCHIVE_DAYS` | Archive files with date ≤ N days ago (negative = relative) | `-3` (all files 3+ days old) |
| `COMPRESS_LEVEL` | gzip compression level (1‑9) | `6` |
| `MAX_CONCURRENT` | Number of parallel `mv` jobs | `4` |
| `LOG_FILE` | Where to write logs | `"/var/log/compress_dump.log"` |

- Note: ARCHIVE_DAYS uses a negative value for “older than or equal to X days”. Example: -3 means “files dated today‑3 or earlier”.

## 🕒 Scheduling with Cron
Add a line to your crontab (edit with crontab -e). Example – run every 2 hours:

```bash
0 */2 * * * /path/to/compress_dump.sh
```

## 📂 File Naming & Matching
The script extracts the date from the last underscore‑separated field of the filename, expecting a 14‑digit timestamp (YYYYMMDDHHMMSS). The first 8 digits become the grouping date.

Example filenames that work:

RB.EVENT_USAGE_2747_20260330150406.dump → date 20260330

SCHEMA.EXP_20260327_120000.dump → date 20260327

All files containing _YYYYMMDD anywhere in the name (i.e., *_YYYYMMDD*.dump) will be moved together.

## 🔧 How It Works (Step by Step)
1. Calculate cutoff date based on ARCHIVE_DAYS.

2. Build a list of unique dates from all .dump files that meet the age condition.

3. For each date, move matching files into a subdirectory inside TEMP_WORK_ROOT (parallel mv).

4. cd into that subdirectory and run tar -c . | gzip -N > ${BACKUP_DIR}/${date}.tar.gz.

5. Remove the temporary subdirectory.

6. Log every action.
