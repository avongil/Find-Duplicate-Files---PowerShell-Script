#!/bin/bash

# find-duplicates.sh
# Identifies duplicate files by size and content hash, or by filename + size only

# Default values
COMPARE_MODE="sha256"
EXPORT_PATH=""
MAX_FILES_TO_DISPLAY=10
SHOW_PROGRESS=false
PATHS=()
EXCLUDES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;90m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Help function
show_help() {
    cat << EOF
Usage: $0 -p PATH1 [-p PATH2 ...] [OPTIONS]

Identifies duplicate files on specified paths by size and content hash,
or alternatively by filename + size only (fast pre-check).

Required:
  -p, --path PATH          Path(s) to scan (can be specified multiple times)

Options:
  -m, --mode MODE          Comparison mode: sha256 (default), sha1, md5, nands
  -e, --export PATH        Export results to CSV file
  -x, --exclude PATH       Path(s) to exclude (can be specified multiple times)
  -d, --display NUM        Max files to display per group (default: 10)
  -s, --show-progress      Show progress information
  -h, --help               Show this help message

Comparison modes:
  sha256  - Most accurate, slowest (default)
  sha1    - Balanced
  md5     - Fastest hash but less collision-resistant
  nands   - Filename (case-insensitive) + size only - very fast, first-pass check

Examples:
  $0 -p /mnt/drive1 -p /mnt/drive2 -m nands -e duplicates.csv
  $0 -p /home/user/Documents -m sha256 -d 5 -s
  $0 -p /data -x /data/backup -x /data/.git -m sha256 -s
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--path)
            PATHS+=("$2")
            shift 2
            ;;
        -m|--mode)
            COMPARE_MODE=$(echo "$2" | tr '[:upper:]' '[:lower:]')
            shift 2
            ;;
        -e|--export)
            EXPORT_PATH="$2"
            shift 2
            ;;
        -x|--exclude)
            EXCLUDES+=("$2")
            shift 2
            ;;
        -d|--display)
            MAX_FILES_TO_DISPLAY="$2"
            shift 2
            ;;
        -s|--show-progress)
            SHOW_PROGRESS=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            show_help
            ;;
    esac
done

# Validate paths
if [ ${#PATHS[@]} -eq 0 ]; then
    echo -e "${RED}Error: At least one path is required${NC}"
    show_help
fi

for path in "${PATHS[@]}"; do
    if [ ! -d "$path" ]; then
        echo -e "${RED}Error: Path does not exist or is not a directory: $path${NC}"
        exit 1
    fi
done

# Validate compare mode
if [[ ! "$COMPARE_MODE" =~ ^(sha256|sha1|md5|nands)$ ]]; then
    echo -e "${RED}Error: Invalid comparison mode: $COMPARE_MODE${NC}"
    echo "Valid modes: sha256, sha1, md5, nands"
    exit 1
fi

echo -e "${CYAN}Scanning for duplicates in: ${PATHS[*]}${NC}"
if [ ${#EXCLUDES[@]} -gt 0 ]; then
    echo -e "${CYAN}Excluding: ${EXCLUDES[*]}${NC}"
fi
echo -e "${CYAN}Comparison mode: $COMPARE_MODE${NC}"

if [ "$COMPARE_MODE" = "nands" ]; then
    echo -e "${YELLOW}Fast mode: matching by filename (case-insensitive) + size only${NC}"
else
    echo -e "${CYAN}Using hash algorithm: $COMPARE_MODE${NC}"
    echo -e "${YELLOW}This may take considerable time on large directories...${NC}"
fi

# Temporary files
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

ALL_FILES="$TMP_DIR/all_files.txt"
DUPLICATES="$TMP_DIR/duplicates.txt"

# Collect all files
if [ "$SHOW_PROGRESS" = true ]; then
    echo -e "\n${CYAN}[$(date +%H:%M:%S)] Starting file enumeration...${NC}"
fi

file_count=0

# Build find exclude arguments
FIND_EXCLUDE_ARGS=()
for exclude in "${EXCLUDES[@]}"; do
    FIND_EXCLUDE_ARGS+=(-path "$exclude" -prune -o)
done

for path in "${PATHS[@]}"; do
    if [ "$SHOW_PROGRESS" = true ]; then
        echo -e "${CYAN}[$(date +%H:%M:%S)] Scanning path: $path${NC}"
    fi
    
    if [ "$SHOW_PROGRESS" = true ]; then
        if [ ${#FIND_EXCLUDE_ARGS[@]} -gt 0 ]; then
            find "$path" "${FIND_EXCLUDE_ARGS[@]}" -type f -print 2>/dev/null | while IFS= read -r file; do
                echo "$file" >> "$ALL_FILES"
                ((file_count++))
                if [ $((file_count % 1000)) -eq 0 ]; then
                    echo -ne "${GRAY}[$(date +%H:%M:%S)] Found $file_count files...\r${NC}"
                fi
            done
        else
            find "$path" -type f 2>/dev/null | while IFS= read -r file; do
                echo "$file" >> "$ALL_FILES"
                ((file_count++))
                if [ $((file_count % 1000)) -eq 0 ]; then
                    echo -ne "${GRAY}[$(date +%H:%M:%S)] Found $file_count files...\r${NC}"
                fi
            done
        fi
    else
        if [ ${#FIND_EXCLUDE_ARGS[@]} -gt 0 ]; then
            find "$path" "${FIND_EXCLUDE_ARGS[@]}" -type f -print 2>/dev/null >> "$ALL_FILES"
        else
            find "$path" -type f 2>/dev/null >> "$ALL_FILES"
        fi
    fi
done

if [ "$SHOW_PROGRESS" = true ]; then
    echo -ne "\n"
fi

total_files=$(wc -l < "$ALL_FILES" 2>/dev/null || echo 0)

if [ "$total_files" -eq 0 ]; then
    echo -e "${GREEN}No files found in the specified path(s).${NC}"
    exit 0
fi

echo -e "${CYAN}Found $total_files files. Analyzing...${NC}"

if [ "$SHOW_PROGRESS" = true ]; then
    echo -e "${CYAN}[$(date +%H:%M:%S)] Starting duplicate analysis...${NC}"
fi

# Function to get file size
get_file_size() {
    stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null
}

# Function to format number with commas
format_number() {
    printf "%'d" "$1" 2>/dev/null || echo "$1"
}

# NandS mode - filename + size only
if [ "$COMPARE_MODE" = "nands" ]; then
    if [ "$SHOW_PROGRESS" = true ]; then
        echo -e "${CYAN}[$(date +%H:%M:%S)] Grouping files by name and size...${NC}"
    fi

    # Create file with: lowercase_filename|size|full_path
    TMP_GROUPED="$TMP_DIR/grouped.txt"
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            filename=$(basename "$file" | tr '[:upper:]' '[:lower:]')
            size=$(get_file_size "$file")
            echo "${filename}|${size}|${file}" >> "$TMP_GROUPED"
        fi
    done < "$ALL_FILES"

    # Find duplicates (same name and size)
    sort "$TMP_GROUPED" | awk -F'|' '{key=$1"|"$2; paths[key]=paths[key]$3"\n"; count[key]++} END {for(k in count) if(count[k]>1) print k"|"count[k]"|"paths[k]}' > "$DUPLICATES"

    duplicate_groups=$(wc -l < "$DUPLICATES")

    if [ "$SHOW_PROGRESS" = true ]; then
        echo -e "${CYAN}[$(date +%H:%M:%S)] Grouping complete. Found $duplicate_groups duplicate groups.${NC}"
    fi

    if [ "$duplicate_groups" -eq 0 ]; then
        echo -e "${GREEN}No files with identical name (case-insensitive) and size found.${NC}"
        exit 0
    fi

    echo -e "\n${MAGENTA}Potential duplicate groups (Name + Size match) - $duplicate_groups groups:${NC}"

    # Prepare CSV if needed
    if [ -n "$EXPORT_PATH" ]; then
        echo "Name,DupeNumber,SizeBytes,Path1,Path2" > "$EXPORT_PATH"
    fi

    # Process each duplicate group
    while IFS='|' read -r name size count paths; do
        formatted_size=$(format_number "$size")
        echo -e "\n${YELLOW}Name: $name   Size: $formatted_size bytes   - $count files${NC}"

        # Split paths into array
        mapfile -t file_array <<< "$paths"
        
        # Remove empty entries and filter non-empty
        clean_array=()
        for file in "${file_array[@]}"; do
            if [ -n "$file" ] && [ "$file" != " " ]; then
                clean_array+=("$file")
            fi
        done
        
        # Display files (limited by MAX_FILES_TO_DISPLAY)
        displayed=0
        for file in "${clean_array[@]}"; do
            if [ $displayed -lt $MAX_FILES_TO_DISPLAY ]; then
                echo -e "${WHITE}  $file${NC}"
                displayed=$((displayed + 1))
            fi
        done

        # Generate pairs for CSV
        if [ -n "$EXPORT_PATH" ]; then
            filename=$(basename "${clean_array[0]}")
            
            # If we have more duplicates than the display limit, only show first and last pair
            if [ ${#clean_array[@]} -gt $MAX_FILES_TO_DISPLAY ]; then
                # First pair (dupe #1)
                if [ ${#clean_array[@]} -ge 2 ]; then
                    echo "\"$filename\",1,$size,\"${clean_array[0]}\",\"${clean_array[1]}\"" >> "$EXPORT_PATH"
                fi
                
                # Last pair (dupe #N)
                last_idx=$((${#clean_array[@]} - 1))
                second_last_idx=$((${#clean_array[@]} - 2))
                if [ $last_idx -gt 1 ]; then
                    echo "\"$filename\",${#clean_array[@]},$size,\"${clean_array[$second_last_idx]}\",\"${clean_array[$last_idx]}\"" >> "$EXPORT_PATH"
                fi
            else
                # Output all pairs with sequential numbering
                pair_num=1
                for ((i=0; i<${#clean_array[@]}; i++)); do
                    for ((j=i+1; j<${#clean_array[@]}; j++)); do
                        echo "\"$filename\",$pair_num,$size,\"${clean_array[i]}\",\"${clean_array[j]}\"" >> "$EXPORT_PATH"
                        ((pair_num++))
                    done
                done
            fi
        fi

        # Show summary if truncated
        if [ $count -gt $MAX_FILES_TO_DISPLAY ]; then
            remaining=$((count - MAX_FILES_TO_DISPLAY))
            first_file=$(basename "${clean_array[0]}")
            last_file=$(basename "${clean_array[-1]}")
            echo -e "${GRAY}  ... and $remaining more files${NC}"
            echo -e "${GRAY}  (Total: $count duplicate files from '$first_file' to '$last_file')${NC}"
        fi
    done < "$DUPLICATES"

# Hash-based modes
else
    if [ "$SHOW_PROGRESS" = true ]; then
        echo -e "${CYAN}[$(date +%H:%M:%S)] Grouping files by size...${NC}"
    fi

    # Group by size first
    TMP_BY_SIZE="$TMP_DIR/by_size.txt"
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            size=$(get_file_size "$file")
            echo "${size}|${file}" >> "$TMP_BY_SIZE"
        fi
    done < "$ALL_FILES"

    # Find sizes with multiple files
    TMP_CANDIDATES="$TMP_DIR/candidates.txt"
    sort "$TMP_BY_SIZE" | awk -F'|' '{size=$1; files[size]=files[size]$2"\n"; count[size]++} END {for(s in count) if(count[s]>1) print files[s]}' | grep -v '^$' > "$TMP_CANDIDATES"

    candidate_count=$(wc -l < "$TMP_CANDIDATES")

    if [ "$SHOW_PROGRESS" = true ]; then
        echo -e "${CYAN}[$(date +%H:%M:%S)] Found files with matching sizes.${NC}"
    fi

    if [ "$candidate_count" -eq 0 ]; then
        echo -e "${GREEN}No files with matching sizes found. No duplicates possible.${NC}"
        exit 0
    fi

    echo -e "${CYAN}Computing hashes for $candidate_count candidate files...${NC}"

    if [ "$SHOW_PROGRESS" = true ]; then
        echo -e "${CYAN}[$(date +%H:%M:%S)] Computing $COMPARE_MODE hashes for $candidate_count candidate files...${NC}"
    fi

    # Compute hashes
    TMP_HASHES="$TMP_DIR/hashes.txt"
    processed=0
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            hash=$(${COMPARE_MODE}sum "$file" 2>/dev/null | awk '{print $1}')
            size=$(get_file_size "$file")
            if [ -n "$hash" ]; then
                echo "${hash}|${size}|${file}" >> "$TMP_HASHES"
            fi
            
            if [ "$SHOW_PROGRESS" = true ]; then
                ((processed++))
                percent=$((processed * 100 / candidate_count))
                echo -ne "${GRAY}[$(date +%H:%M:%S)] Progress: $processed/$candidate_count ($percent%)\r${NC}"
            fi
        fi
    done < "$TMP_CANDIDATES"

    if [ "$SHOW_PROGRESS" = true ]; then
        echo -ne "\n${CYAN}[$(date +%H:%M:%S)] Hash computation complete.${NC}\n"
    fi

    # Find duplicate hashes
    sort "$TMP_HASHES" | awk -F'|' '{hash=$1; size=$2; paths[hash]=paths[hash]$3"\n"; sizes[hash]=size; count[hash]++} END {for(h in count) if(count[h]>1) print h"|"sizes[h]"|"count[h]"|"paths[h]}' > "$DUPLICATES"

    duplicate_groups=$(wc -l < "$DUPLICATES")

    if [ "$duplicate_groups" -eq 0 ]; then
        echo -e "${GREEN}No duplicate files found (no matching content hashes).${NC}"
        exit 0
    fi

    echo -e "\n${MAGENTA}Duplicate file groups found - $duplicate_groups groups:${NC}"

    # Prepare CSV if needed
    if [ -n "$EXPORT_PATH" ]; then
        echo "Name,DupeNumber,SizeBytes,Path1,Path2" > "$EXPORT_PATH"
    fi

    # Process each duplicate group
    while IFS='|' read -r hash size count paths; do
        echo -e "\n${YELLOW}Hash: $hash  - $count files${NC}"

        # Split paths into array
        mapfile -t file_array <<< "$paths"
        
        # Remove empty entries and filter non-empty
        clean_array=()
        for file in "${file_array[@]}"; do
            if [ -n "$file" ] && [ "$file" != " " ]; then
                clean_array+=("$file")
            fi
        done
        
        # Display files (limited by MAX_FILES_TO_DISPLAY)
        displayed=0
        for file in "${clean_array[@]}"; do
            if [ $displayed -lt $MAX_FILES_TO_DISPLAY ]; then
                echo -e "${WHITE}  $file${NC}"
                displayed=$((displayed + 1))
            fi
        done

        # Generate pairs for CSV
        if [ -n "$EXPORT_PATH" ] && [ ${#clean_array[@]} -gt 0 ]; then
            filename=$(basename "${clean_array[0]}")
            
            # If we have more duplicates than the display limit, only show first and last pair
            if [ ${#clean_array[@]} -gt $MAX_FILES_TO_DISPLAY ]; then
                # First pair (dupe #1)
                if [ ${#clean_array[@]} -ge 2 ]; then
                    echo "\"$filename\",1,$size,\"${clean_array[0]}\",\"${clean_array[1]}\"" >> "$EXPORT_PATH"
                fi
                
                # Last pair (dupe #N)
                last_idx=$((${#clean_array[@]} - 1))
                second_last_idx=$((${#clean_array[@]} - 2))
                if [ $last_idx -gt 1 ]; then
                    echo "\"$filename\",${#clean_array[@]},$size,\"${clean_array[$second_last_idx]}\",\"${clean_array[$last_idx]}\"" >> "$EXPORT_PATH"
                fi
            else
                # Output all pairs with sequential numbering
                pair_num=1
                for ((i=0; i<${#clean_array[@]}; i++)); do
                    for ((j=i+1; j<${#clean_array[@]}; j++)); do
                        echo "\"$filename\",$pair_num,$size,\"${clean_array[i]}\",\"${clean_array[j]}\"" >> "$EXPORT_PATH"
                        ((pair_num++))
                    done
                done
            fi
        fi

        # Show summary if truncated
        if [ $count -gt $MAX_FILES_TO_DISPLAY ]; then
            remaining=$((count - MAX_FILES_TO_DISPLAY))
            first_file=$(basename "${clean_array[0]}")
            last_file=$(basename "${clean_array[-1]}")
            echo -e "${GRAY}  ... and $remaining more files${NC}"
            echo -e "${GRAY}  (Total: $count duplicate files from '$first_file' to '$last_file')${NC}"
        fi
    done < "$DUPLICATES"
fi

# Export notification
if [ -n "$EXPORT_PATH" ]; then
    echo -e "\n${GREEN}Results exported to: $EXPORT_PATH${NC}"
fi

echo -e "\n${CYAN}Scan complete.${NC}"
