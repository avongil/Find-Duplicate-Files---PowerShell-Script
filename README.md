# Find-Duplicate-Files---Bash-Script
there is now a linux version of this script:


Bash script example:


sudo ./find-duplicates.sh \
    -p /srv \
    -x /srv/GMT_DATA/Cobian_Incremental_NextcloudGMT_Backup \
    -m nands \
    -d 3 \
    -e /srv/GMT_DATA/duplicates_bash.csv \
&& sudo chown alvaro:alvaro /srv/GMT_DATA/duplicates_bash.csv \
&& sudo chmod 660 /srv/GMT_DATA/duplicates_bash.csv
----

alternatley, you may try using rmlint instead.  First install rmlint to on your system then:

"rmlint \
  -b \
  -F \
  --no-hardlinked \
  /dirtoscan/ \
sudo mv ~r/rmlint.json /srv/GMT_DATA/rmlint.json \
&& sudo chown alvaro:alvaro /srv/GMT_DATA/rmlint.json \
&& sudo chmod 660 /srv/GMT_DATA/rmlint.json"




# Find-Duplicate-Files---PowerShell-Script
Finds duplicate files and writes a CSV file so you can delete them manually

Example:  
.\Find-DuplicateFiles.ps1 -Path 'X:\', 'W:\' -Exclude 'X:\Cobian_Incremental_NextcloudGMT_Backup' -CompareMode NandS -MaxFilesToDisplay 3 -ShowProgress -ExportPath '\Scripts\FindDuplicates\dupes-kirk.csv'

Finds all duplicate files in X:\ and W:\   Excludes the directory X:\Cobian_Incremental_NextcloudGMT_Backup  Compares only the Filename and Sizes  is verbose with a progress indicator  then exports the results to \Scripts\FindDuplicates\dupes-kirk.csv

---

.SYNOPSIS
    Identifies duplicate files on a network drive or folder by size and content hash,
    or alternatively by filename + size only (fast pre-check).

.DESCRIPTION
    Recursively scans the specified path(s).
    - Default / hash mode: groups files by size → computes selected hash → finds true duplicates
    - NameAndSize mode: groups files by filename (case-insensitive) + size → reports likely duplicates
    Results are displayed in console and can be exported to CSV.

.PARAMETER Path
    The root path(s) to scan (accepts array).

.PARAMETER Exclude
    Optional array of folder paths/patterns to exclude (not yet implemented in this version).

.PARAMETER CompareMode
    Determines how duplicates are detected:
    - SHA256  (default) → most accurate, slowest
    - SHA1    → balanced
    - MD5     → fastest hash but less collision-resistant
    - NandS   → filename (case-insensitive) + size only → very fast, first-pass check

.PARAMETER ExportPath
    Optional: Full path to export results as CSV.

.PARAMETER MaxFilesToDisplay
    Maximum number of files to display per duplicate group before summarizing (default: 10).

.PARAMETER ShowProgress
    Display detailed progress information during scanning and processing.

.EXAMPLE
    .\Find-DuplicateFiles.ps1 -Path 'X:\', 'W:\' -CompareMode NandS -ExportPath 'C:\dupes.csv'

.EXAMPLE
    .\Find-DuplicateFiles.ps1 -Path 'X:\' -CompareMode SHA256 -MaxFilesToDisplay 5 -ShowProgress
