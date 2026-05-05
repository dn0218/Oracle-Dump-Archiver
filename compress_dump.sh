#!/bin/bash

# ================== 环境配置 ==================
# 存放 .dump 文件的源目录（可多个，空格分隔）
SOURCE_DIRS=(
    "/oracle/target"          # 示例路径，请按实际修改
    # "/another/dump/path"
)

# 归档目标目录（压缩后的 .tar.gz 存放位置）
BACKUP_DIR="/oracle/backup/dump_archives"

# 临时工作根目录（建议与源目录在同一文件系统，避免跨设备移动）
TEMP_WORK_ROOT="/tmp/dump_compress_work"

# 归档策略：只处理 N 天前及更早的文件（负数表示 N 天前，如 -3 表示 3 天前及之前）
ARCHIVE_DAYS=-10

# gzip 压缩级别（1-9，6 为默认）
COMPRESS_LEVEL=6

# 并行移动文件的最大并发数（根据 CPU/磁盘性能调整）
MAX_CONCURRENT=4

# 日志文件路径（确保目录存在且有写权限）
LOG_FILE="/oracle/target/compress_dump.log"

# ================== 函数定义 ==================
log_message() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
}

# 从 .dump 文件名中提取日期（YYYYMMDD）
# 格式示例：RB.EVENT_USAGE_2747_20260330150406.dump
extract_date_from_filename() {
    local filename="$1"
    local base="${filename%.dump}"
    local last_field=$(echo "$base" | rev | cut -d'_' -f1 | rev)
    if [[ "$last_field" =~ ^[0-9]{14}$ ]]; then
        echo "${last_field:0:8}"
    else
        echo ""
    fi
}

# 判断文件日期是否满足归档条件（<= cutoff_date）
should_archive_date() {
    local file_date="$1"
    local cutoff="$2"
    [[ "$file_date" -le "$cutoff" ]]
}

# 扫描所有源目录，收集满足条件的文件日期（去重）
collect_dates() {
    local cutoff_date="$1"
    local dates_file="$2"
    for src_dir in "${SOURCE_DIRS[@]}"; do
        [ ! -d "$src_dir" ] && continue
        find "$src_dir" -maxdepth 1 -name '*.dump' -type f -print0 2>/dev/null | \
        while IFS= read -r -d '' file; do
            local base=$(basename "$file")
            local file_date=$(extract_date_from_filename "$base")
            if [ -n "$file_date" ] && should_archive_date "$file_date" "$cutoff_date"; then
                echo "$file_date"
            fi
        done
    done | sort -u > "$dates_file"
}

# 移动指定日期的所有 .dump 文件到临时工作目录下的子目录
move_files_by_date() {
    local target_date="$1"
    local work_dir="$2"
    local dest_dir="$work_dir/$target_date"
    mkdir -p "$dest_dir" || {
        log_message "ERROR: Cannot create $dest_dir"
        return 1
    }
    local total_moved=0
    for src_dir in "${SOURCE_DIRS[@]}"; do
        [ ! -d "$src_dir" ] && continue
        local moved=0
        while IFS= read -r -d '' file; do
            if mv "$file" "$dest_dir/" 2>>"$LOG_FILE"; then
                moved=$((moved + 1))
                total_moved=$((total_moved + 1))
            else
                log_message "ERROR: Failed to move $(basename "$file")"
            fi
        done < <(find "$src_dir" -maxdepth 1 -name "*_${target_date}*.dump" -type f -print0 2>/dev/null)
        [ "$moved" -gt 0 ] && log_message "Moved $moved file(s) from $src_dir for date $target_date"
    done
    [ "$total_moved" -eq 0 ] && rmdir "$dest_dir" 2>/dev/null
    log_message "Total moved for date $target_date: $total_moved file(s)"
}

# 打包并压缩某个日期的临时目录，生成 .tar.gz
archive_date() {
    local target_date="$1"
    local work_dir="$2"
    local date_dir="$work_dir/$target_date"
    if [ ! -d "$date_dir" ] || [ -z "$(ls -A "$date_dir")" ]; then
        log_message "No files for date $target_date, skipping"
        return 0
    fi
    local final_file="${BACKUP_DIR}/CDR_BAK_${target_date}_dump.tar.gz"
    mkdir -p "$(dirname "$final_file")"
    log_message "Creating archive: $final_file"
    (cd "$date_dir" && tar --create --file=- .) | \
        gzip -${COMPRESS_LEVEL} > "$final_file" 2>>"$LOG_FILE"
    if [ $? -eq 0 ] && [ -s "$final_file" ]; then
        local size=$(du -h "$final_file" | awk '{print $1}')
        log_message "SUCCESS: Archive $target_date.tar.gz created, size: $size"
        # 打包成功后删除临时目录中的原始文件
        rm -rf "$date_dir"
    else
        log_message "ERROR: Failed to create archive for $target_date"
        return 1
    fi
}

# 主执行逻辑（单次运行）
run_compression() {
    log_message "===== Starting compression job ====="
    # 计算截止日期（ARCHIVE_DAYS 天前）
    local cutoff_days=${ARCHIVE_DAYS#-}
    local cutoff_date=$(date --date="${cutoff_days} days ago" '+%Y%m%d' 2>/dev/null)
    if [ -z "$cutoff_date" ]; then
        log_message "ERROR: Failed to calculate cutoff date"
        return 1
    fi
    log_message "Archive policy: files with date <= $cutoff_date (${ARCHIVE_DAYS} days ago)"

    # 创建临时工作根目录
    mkdir -p "$TEMP_WORK_ROOT"
    chmod 700 "$TEMP_WORK_ROOT"
    local work_dir=$(mktemp -d -p "$TEMP_WORK_ROOT" "dump_work_XXXXXX")
    chmod 700 "$work_dir"
    log_message "Using temp work directory: $work_dir"

    # 收集待处理日期
    local dates_file=$(mktemp -p "$TEMP_WORK_ROOT" "dates_XXXXXX")
    collect_dates "$cutoff_date" "$dates_file"
    if [ ! -s "$dates_file" ]; then
        log_message "No .dump files found matching archive policy. Exiting."
        rm -rf "$work_dir" "$dates_file"
        return 0
    fi
    log_message "Dates to archive: $(tr '\n' ' ' < "$dates_file")"

    # 并行移动文件（每个日期一个独立任务）
    local pids=()
    while IFS= read -r date_to_archive; do
        [ -z "$date_to_archive" ] && continue
        move_files_by_date "$date_to_archive" "$work_dir" &
        pids+=($!)
        # 控制并发数
        while [ ${#pids[@]} -ge $MAX_CONCURRENT ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 ${pids[$i]} 2>/dev/null; then
                    unset 'pids[$i]'
                fi
            done
            pids=("${pids[@]}")
            sleep 1
        done
    done < "$dates_file"
    # 等待所有移动任务完成
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null
    done

    # 对每个日期执行打包压缩
    while IFS= read -r date_to_archive; do
        [ -z "$date_to_archive" ] && continue
        archive_date "$date_to_archive" "$work_dir"
    done < "$dates_file"

    # 清理临时目录和日期文件
    rm -rf "$work_dir" "$dates_file"
    log_message "===== Compression job finished ====="
}

# ================== 主程序 ==================
# 检查必要工具
if ! command -v gzip &>/dev/null; then
    echo "FATAL: gzip not found. Please install gzip." | tee -a "$LOG_FILE"
    exit 1
fi
if ! command -v tar &>/dev/null; then
    echo "FATAL: tar not found." | tee -a "$LOG_FILE"
    exit 1
fi

# 创建日志目录
if [ -n "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
fi

log_message "Dump compression script (single-run mode) started"
log_message "Source directories: ${SOURCE_DIRS[*]}"
log_message "Backup directory: $BACKUP_DIR"
log_message "Archive days: $ARCHIVE_DAYS"
log_message "gzip level: $COMPRESS_LEVEL"

run_compression

log_message "Script finished successfully"
exit 0
