#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Normalize project and file names inside a sorted Pokemon directory.

Usage:
  normalize_sorted_names.sh [--sorted-dir <path>] [--dry-run|--apply] [--shortcut-type <preserve|alias|symlink>] [--verbose]

Options:
  --sorted-dir <path>  Sorted root directory. Default: ./Sorted by Pokemon
  --dry-run            Plan only (default)
  --apply              Perform renames and recreate project shortcuts (symlink or alias)
  --shortcut-type      Shortcut recreation mode: preserve, alias, symlink (default: preserve)
  --alias-shortcuts    Recreate all shortcuts as Finder aliases
  --symlink-shortcuts  Recreate all shortcuts as symbolic links
  --preserve-shortcuts Preserve existing shortcut type per entry (default)
  --verbose            Print detailed rename actions
  -h, --help           Show help
EOF
}

err() {
  echo "Error: $*" >&2
  exit 1
}

upper_ascii() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

trim_spaces() {
  printf '%s' "$1" | sed 's/^[[:space:]]\+//; s/[[:space:]]\+$//'
}

normalize_project_name() {
  local raw="$1"
  local core
  local normalized
  local stem
  local variant_num

  core="$(trim_spaces "$raw")"
  if [[ "$core" == *" - "* ]]; then
    core="${core#* - }"
  fi
  core="$(trim_spaces "$core")"

  if [[ "$core" =~ ^(.*)[[:space:]]+\(Variant[[:space:]]+([0-9]+)\)$ ]]; then
    stem="$(trim_spaces "${BASH_REMATCH[1]}")"
    variant_num="${BASH_REMATCH[2]}"
    normalized="$(to_title_case "$stem")"
    printf '%s (Variant %s)' "$normalized" "$variant_num"
    return
  fi

  normalized="$(to_title_case "$core")"
  printf '%s' "$normalized"
}

to_title_case() {
  local value="$1"
  perl -e '
    use strict;
    use warnings;
    my $s = shift // "";
    $s = lc $s;
    $s =~ s/&/ and /g;
    $s =~ s/\bgrooky\b/grookey/g;
    $s =~ s/\bscrobunny\b/scorbunny/g;
    $s =~ s/\bpipliup\b/piplup/g;
    $s =~ s/\bwobbebuffet\b/wobbuffet/g;
    $s =~ s/\bsmorelax\b/snorlax/g;
    $s =~ s/\bvaporon\b/vaporeon/g;
    $s =~ s/\bsleping\b/sleeping/g;
    $s =~ s/\bcolr\b/color/g;
    $s =~ s/\bclsy\b/clay/g;
    $s =~ s/[_\-]+/ /g;
    $s =~ s/[^a-z0-9 ]+/ /g;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    my @out;
    for my $w (split / /, $s) {
      next if $w eq "";
      if ($w =~ /^\d+$/) {
        push @out, $w;
        next;
      }
      if ($w eq "mmu") { push @out, "MMU"; next; }
      if ($w eq "fdm") { push @out, "FDM"; next; }
      if ($w eq "stl") { push @out, "STL"; next; }
      if ($w eq "gen") { push @out, "Gen"; next; }
      $w =~ s/^([a-z])/\U$1/;
      push @out, $w;
    }
    print join(" ", @out);
  ' "$value"
}

to_snake_component() {
  local stem="$1"
  perl -e '
    use strict;
    use warnings;
    my $s = shift // "";
    $s = lc $s;
    $s =~ s/&/ and /g;
    $s =~ s/\bgrooky\b/grookey/g;
    $s =~ s/\bscrobunny\b/scorbunny/g;
    $s =~ s/\bpipliup\b/piplup/g;
    $s =~ s/\bwobbebuffet\b/wobbuffet/g;
    $s =~ s/\bsmorelax\b/snorlax/g;
    $s =~ s/\bvaporon\b/vaporeon/g;
    $s =~ s/\bsleping\b/sleeping/g;
    $s =~ s/\bcolr\b/color/g;
    $s =~ s/\bclsy\b/clay/g;
    $s =~ s/[^a-z0-9]+/_/g;
    $s =~ s/_+/_/g;
    $s =~ s/^_+|_+$//g;
    $s = "item" if $s eq "";
    print $s;
  ' "$stem"
}

normalize_file_name() {
  local base="$1"
  local stem="$base"
  local ext=""
  local new_stem
  local new_ext

  if [[ "$base" == *.* && "$base" != .* ]]; then
    stem="${base%.*}"
    ext="${base##*.}"
  fi

  new_stem="$(to_snake_component "$stem")"
  if [ -n "$ext" ]; then
    new_ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    if [ -z "$new_ext" ]; then
      printf '%s' "$new_stem"
    else
      printf '%s.%s' "$new_stem" "$new_ext"
    fi
  else
    printf '%s' "$new_stem"
  fi
}

relative_path() {
  local from_dir="$1"
  local to_path="$2"
  perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[1], $ARGV[0])' "$from_dir" "$to_path"
}

resolve_abs_path() {
  local path="$1"
  perl -MCwd=abs_path -e 'my $p = abs_path($ARGV[0]); print $p if defined $p' "$path"
}

resolve_finder_alias_target() {
  local alias_abs="$1"
  ALIAS_POSIX="$alias_abs" osascript 2>/dev/null <<'APPLESCRIPT' || true
try
  tell application "Finder"
    set aliasRef to POSIX file (system attribute "ALIAS_POSIX") as alias
    set targetRef to original item of aliasRef as alias
    return POSIX path of targetRef
  end tell
on error
  return ""
end try
APPLESCRIPT
}

create_finder_alias() {
  local target_abs="$1"
  local alias_abs="$2"
  local alias_dir
  local created_abs
  local osa_out_try1=""
  local osa_out_try2=""
  local attempt

  alias_dir="$(dirname "$alias_abs")"

  # Try modern Finder form first.
  for attempt in 1 2; do
    if created_abs="$(
      TARGET_POSIX="$target_abs" DEST_POSIX="$alias_dir" \
        osascript 2>&1 <<'APPLESCRIPT'
tell application "Finder"
  set targetItem to POSIX file (system attribute "TARGET_POSIX") as alias
  set destinationFolder to POSIX file (system attribute "DEST_POSIX") as alias
  set newAlias to make new alias file to targetItem at destinationFolder
  return POSIX path of (newAlias as alias)
end tell
APPLESCRIPT
    )"; then
      created_abs="$(printf '%s' "$created_abs" | tr -d '\r\n')"
      [ -n "$created_abs" ] || err "Finder created an alias but did not return its path: $alias_abs -> $target_abs"
      if [ "$created_abs" != "$alias_abs" ]; then
        mv "$created_abs" "$alias_abs"
      fi
      return 0
    fi
    osa_out_try1="$created_abs"
    sleep 0.2
  done

  # Fallback for older Finder scripting variants.
  for attempt in 1 2; do
    if created_abs="$(
      TARGET_POSIX="$target_abs" DEST_POSIX="$alias_dir" \
        osascript 2>&1 <<'APPLESCRIPT'
tell application "Finder"
  set targetItem to POSIX file (system attribute "TARGET_POSIX") as alias
  set destinationFolder to POSIX file (system attribute "DEST_POSIX") as alias
  set newAlias to make alias file to targetItem at destinationFolder
  return POSIX path of (newAlias as alias)
end tell
APPLESCRIPT
    )"; then
      created_abs="$(printf '%s' "$created_abs" | tr -d '\r\n')"
      [ -n "$created_abs" ] || err "Finder created an alias but did not return its path: $alias_abs -> $target_abs"
      if [ "$created_abs" != "$alias_abs" ]; then
        mv "$created_abs" "$alias_abs"
      fi
      return 0
    fi
    osa_out_try2="$created_abs"
    sleep 0.2
  done

  err "Failed to create Finder alias: $alias_abs -> $target_abs"$'\n'"Attempt 1 output:"$'\n'"$osa_out_try1"$'\n'"Attempt 2 output:"$'\n'"$osa_out_try2"
}

inode_key() {
  stat -f '%d:%i' "$1" 2>/dev/null || true
}

desired_shortcut_kind() {
  local source_kind="$1"
  case "$SHORTCUT_TYPE_MODE" in
    preserve)
      printf '%s' "$source_kind"
      ;;
    alias)
      printf '%s' "alias"
      ;;
    symlink)
      printf '%s' "symlink"
      ;;
    *)
      err "Unsupported shortcut mode: $SHORTCUT_TYPE_MODE"
      ;;
  esac
}

MODE="dry-run"
VERBOSE=0
SORTED_DIR="./Sorted by Pokemon"
SHORTCUT_TYPE_MODE="preserve"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sorted-dir)
      shift
      [ "$#" -gt 0 ] || err "--sorted-dir requires a value"
      SORTED_DIR="$1"
      ;;
    --dry-run)
      MODE="dry-run"
      ;;
    --apply)
      MODE="apply"
      ;;
    --shortcut-type)
      shift
      [ "$#" -gt 0 ] || err "--shortcut-type requires a value"
      case "$1" in
        preserve|alias|symlink)
          SHORTCUT_TYPE_MODE="$1"
          ;;
        *)
          err "--shortcut-type must be 'preserve', 'alias', or 'symlink'"
          ;;
      esac
      ;;
    --alias-shortcuts)
      SHORTCUT_TYPE_MODE="alias"
      ;;
    --symlink-shortcuts)
      SHORTCUT_TYPE_MODE="symlink"
      ;;
    --preserve-shortcuts)
      SHORTCUT_TYPE_MODE="preserve"
      ;;
    --verbose)
      VERBOSE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      ;;
  esac
  shift
done

[ -d "$SORTED_DIR" ] || err "Sorted directory not found: $SORTED_DIR"
SORTED_DIR_ABS="$(cd "$SORTED_DIR" && pwd)"
[ -d "$SORTED_DIR_ABS/_reports" ] || mkdir -p "$SORTED_DIR_ABS/_reports"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/normalize-sorted-names.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

FS=$'\x1f'

CANONICAL_DIRS_FILE="$TMP_DIR/canonical_dirs.txt"
SYMLINK_DIRS_FILE="$TMP_DIR/symlink_dirs.txt"
ALIAS_CANDIDATES_FILE="$TMP_DIR/alias_candidates.txt"
CANONICAL_RAW_FILE="$TMP_DIR/canonical_raw.tsv"
CANONICAL_MAP_FILE="$TMP_DIR/canonical_map.tsv"
SHORTCUT_MAP_FILE="$TMP_DIR/shortcut_map.tsv"
NEW_PATHS_FILE="$TMP_DIR/new_paths.txt"
HAS_OSASCRIPT=0
if command -v osascript >/dev/null 2>&1; then
  HAS_OSASCRIPT=1
fi

find "$SORTED_DIR_ABS" -mindepth 2 -maxdepth 2 -type d | LC_ALL=C sort > "$CANONICAL_DIRS_FILE"
find "$SORTED_DIR_ABS" -mindepth 2 -maxdepth 2 -type l | LC_ALL=C sort > "$SYMLINK_DIRS_FILE"
find "$SORTED_DIR_ABS" -mindepth 2 -maxdepth 2 -type f | LC_ALL=C sort > "$ALIAS_CANDIDATES_FILE"

: > "$CANONICAL_RAW_FILE"
while IFS= read -r canonical_abs; do
  [ -n "$canonical_abs" ] || continue
  rel="${canonical_abs#$SORTED_DIR_ABS/}"
  pokemon="${rel%%/*}"
  [ "$pokemon" != "_reports" ] || continue
  [ "$pokemon" != "_photo_directory" ] || continue
  old_base="${rel#*/}"
  old_base="$(trim_spaces "$old_base")"
  normalized_core="$(normalize_project_name "$old_base")"
  [ -n "$normalized_core" ] || normalized_core="Project"
  lookup_abs="$(resolve_abs_path "$canonical_abs")"
  [ -n "$lookup_abs" ] || lookup_abs="$canonical_abs"

  printf '%s%s%s%s%s%s%s\n' \
    "$lookup_abs" "$FS" \
    "$rel" "$FS" \
    "$pokemon" "$FS" \
    "$normalized_core" >> "$CANONICAL_RAW_FILE"
done < "$CANONICAL_DIRS_FILE"

LC_ALL=C sort -t "$FS" -k3,3 -k4,4 -k2,2 "$CANONICAL_RAW_FILE" | \
awk -F "$FS" -v OFS="$FS" '
  {
    oldAbs[NR] = $1
    oldRel[NR] = $2
    pokemon[NR] = $3
    norm[NR] = $4
    key = pokemon[NR] SUBSEP norm[NR]
    total[key]++
    orderKey[NR] = key
  }
  END {
    for (i = 1; i <= NR; i++) {
      key = orderKey[i]
      seen[key]++
      suffix = ""
      if (total[key] > 1) {
        suffix = " (Variant " seen[key] ")"
      }
      finalBase = norm[i] suffix
      newRel = pokemon[i] "/" finalBase
      print oldAbs[i], oldRel[i], newRel, finalBase
    }
  }
' > "$CANONICAL_MAP_FILE"

: > "$SHORTCUT_MAP_FILE"
while IFS= read -r link_abs; do
  [ -n "$link_abs" ] || continue
  old_rel="${link_abs#$SORTED_DIR_ABS/}"
  link_pokemon="${old_rel%%/*}"
  [ "$link_pokemon" != "_reports" ] || continue
  [ "$link_pokemon" != "_photo_directory" ] || continue

  target_abs="$(resolve_abs_path "$link_abs")"
  [ -n "$target_abs" ] || err "Unable to resolve symlink target: $link_abs"

  target_new_rel="$(awk -F "$FS" -v t="$target_abs" '$1 == t { print $3; exit }' "$CANONICAL_MAP_FILE")"
  [ -n "$target_new_rel" ] || err "No canonical mapping found for symlink target: $link_abs -> $target_abs"

  final_base="${target_new_rel#*/}"
  new_rel="${link_pokemon}/${final_base}"
  source_kind="symlink"
  target_kind="$(desired_shortcut_kind "$source_kind")"
  printf '%s%s%s%s%s%s%s%s%s\n' \
    "$old_rel" "$FS" "$new_rel" "$FS" "$target_new_rel" "$FS" "$source_kind" "$FS" "$target_kind" >> "$SHORTCUT_MAP_FILE"
done < "$SYMLINK_DIRS_FILE"

if [ "$HAS_OSASCRIPT" -eq 1 ]; then
  while IFS= read -r alias_abs; do
    [ -n "$alias_abs" ] || continue
    old_rel="${alias_abs#$SORTED_DIR_ABS/}"
    link_pokemon="${old_rel%%/*}"
    [ "$link_pokemon" != "_reports" ] || continue
    [ "$link_pokemon" != "_photo_directory" ] || continue

    target_abs="$(resolve_finder_alias_target "$alias_abs" | tr -d '\r')"
    target_new_rel=""
    if [ -n "$target_abs" ]; then
      target_new_rel="$(awk -F "$FS" -v t="$target_abs" '$1 == t { print $3; exit }' "$CANONICAL_MAP_FILE")"
    fi

    # Fallback for Finder alias resolution edge-cases:
    # infer canonical target by matching alias basename to canonical old basename.
    if [ -z "$target_new_rel" ]; then
      alias_base="${old_rel#*/}"
      target_new_rel="$(awk -F "$FS" -v b="$alias_base" '
        {
          old_base = $2
          sub(/^[^\/]+\//, "", old_base)
          if (old_base == b) {
            count++
            candidate = $3
          }
        }
        END {
          if (count == 1) {
            print candidate
          }
        }
      ' "$CANONICAL_MAP_FILE")"
    fi

    if [ -z "$target_new_rel" ]; then
      if [ "$VERBOSE" -eq 1 ]; then
        echo "SKIP NON-PROJECT/UNRESOLVED ALIAS: $old_rel"
      fi
      continue
    fi

    final_base="${target_new_rel#*/}"
    new_rel="${link_pokemon}/${final_base}"
    source_kind="alias"
    target_kind="$(desired_shortcut_kind "$source_kind")"
    printf '%s%s%s%s%s%s%s%s%s\n' \
      "$old_rel" "$FS" "$new_rel" "$FS" "$target_new_rel" "$FS" "$source_kind" "$FS" "$target_kind" >> "$SHORTCUT_MAP_FILE"
  done < "$ALIAS_CANDIDATES_FILE"
fi

{
  awk -F "$FS" '{print $3}' "$CANONICAL_MAP_FILE"
  awk -F "$FS" '{print $2}' "$SHORTCUT_MAP_FILE"
} | LC_ALL=C sort > "$NEW_PATHS_FILE"

dup_new_paths="$(uniq -d "$NEW_PATHS_FILE" || true)"
if [ -n "$dup_new_paths" ]; then
  echo "Path collisions detected in planned renames:" >&2
  echo "$dup_new_paths" >&2
  exit 1
fi

project_total="$(wc -l < "$CANONICAL_MAP_FILE" | tr -d ' ')"
shortcut_total="$(wc -l < "$SHORTCUT_MAP_FILE" | tr -d ' ')"
project_rename_total="$(awk -F "$FS" '$2 != $3 {count++} END {print count+0}' "$CANONICAL_MAP_FILE")"
shortcut_rename_total="$(awk -F "$FS" '$1 != $2 {count++} END {print count+0}' "$SHORTCUT_MAP_FILE")"

echo "Sorted directory: $SORTED_DIR_ABS"
echo "Mode: $MODE"
echo "Shortcut recreation mode: $SHORTCUT_TYPE_MODE"
echo "Canonical projects discovered: $project_total"
echo "Shortcuts discovered: $shortcut_total"
echo "Planned project folder renames: $project_rename_total"
echo "Planned shortcut name updates: $shortcut_rename_total"

if [ "$VERBOSE" -eq 1 ] || [ "$MODE" = "dry-run" ]; then
  echo
  echo "Project folder plan:"
  awk -F "$FS" '{printf "PROJECT: %s -> %s\n", $2, $3}' "$CANONICAL_MAP_FILE"
  if [ "$shortcut_total" -gt 0 ]; then
    echo
    echo "Shortcut plan:"
    awk -F "$FS" '{printf "%s->%s: %s -> %s (target: %s)\n", toupper($4), toupper($5), $1, $2, $3}' "$SHORTCUT_MAP_FILE"
  fi
fi

if [ "$MODE" = "dry-run" ]; then
  exit 0
fi

PROJECT_REPORT="$SORTED_DIR_ABS/_reports/name_cleanup_project_map.tsv"
FILE_REPORT="$SORTED_DIR_ABS/_reports/name_cleanup_file_renames.tsv"
printf 'kind\told_path\tnew_path\ttarget\n' > "$PROJECT_REPORT"
printf 'old_path\tnew_path\tkind\n' > "$FILE_REPORT"

while IFS="$FS" read -r old_rel _new_rel _target_new_rel source_kind _target_kind; do
  [ -n "$old_rel" ] || continue
  old_abs="$SORTED_DIR_ABS/$old_rel"
  if [ "$source_kind" = "symlink" ] && [ -L "$old_abs" ]; then
    rm "$old_abs"
    if [ "$VERBOSE" -eq 1 ]; then
      echo "REMOVED OLD LINK: $old_rel"
    fi
  elif [ "$source_kind" = "alias" ] && [ -e "$old_abs" ]; then
    rm "$old_abs"
    if [ "$VERBOSE" -eq 1 ]; then
      echo "REMOVED OLD ALIAS: $old_rel"
    fi
  fi
done < "$SHORTCUT_MAP_FILE"

while IFS="$FS" read -r old_abs old_rel new_rel _final_base; do
  [ -n "$old_abs" ] || continue
  [ -d "$old_abs" ] || err "Canonical project missing: $old_abs"
  new_abs="$SORTED_DIR_ABS/$new_rel"
  mkdir -p "$(dirname "$new_abs")"

  if [ "$old_abs" != "$new_abs" ]; then
    if [ -e "$new_abs" ] || [ -L "$new_abs" ]; then
      err "Target project path already exists: $new_abs"
    fi
    mv "$old_abs" "$new_abs"
    echo -e "project\t$old_rel\t$new_rel\t" >> "$PROJECT_REPORT"
    if [ "$VERBOSE" -eq 1 ]; then
      echo "RENAMED PROJECT: $old_rel -> $new_rel"
    fi
  else
    echo -e "project\t$old_rel\t$new_rel\tunchanged" >> "$PROJECT_REPORT"
  fi
done < "$CANONICAL_MAP_FILE"

while IFS="$FS" read -r old_rel new_rel target_new_rel _source_kind target_kind; do
  [ -n "$new_rel" ] || continue
  link_abs="$SORTED_DIR_ABS/$new_rel"
  target_abs="$SORTED_DIR_ABS/$target_new_rel"
  [ -d "$target_abs" ] || err "Shortcut target missing: $target_abs"
  mkdir -p "$(dirname "$link_abs")"

  if [ -e "$link_abs" ] || [ -L "$link_abs" ]; then
    err "Shortcut destination already exists: $link_abs"
  fi

  if [ "$target_kind" = "alias" ]; then
    if [ "$HAS_OSASCRIPT" -ne 1 ]; then
      err "Cannot recreate alias without osascript: $new_rel"
    fi
    create_finder_alias "$target_abs" "$link_abs"
    echo -e "alias\t${old_rel}\t${new_rel}\t${target_new_rel}" >> "$PROJECT_REPORT"
    if [ "$VERBOSE" -eq 1 ]; then
      echo "CREATED ALIAS: $new_rel -> $target_new_rel"
    fi
  else
    rel_target="$(relative_path "$(dirname "$link_abs")" "$target_abs")"
    ln -s "$rel_target" "$link_abs"
    echo -e "link\t${old_rel}\t${new_rel}\t${target_new_rel}" >> "$PROJECT_REPORT"
    if [ "$VERBOSE" -eq 1 ]; then
      echo "CREATED LINK: $new_rel -> $target_new_rel"
    fi
  fi
done < "$SHORTCUT_MAP_FILE"

internal_rename_count=0

while IFS="$FS" read -r _old_abs _old_rel new_rel _final_base; do
  [ -n "$new_rel" ] || continue
  project_abs="$SORTED_DIR_ABS/$new_rel"
  [ -d "$project_abs" ] || err "Project directory missing after rename: $project_abs"

  while IFS= read -r item; do
    [ -n "$item" ] || continue
    parent="$(dirname "$item")"
    base="$(basename "$item")"
    new_base="$base"

    if [ -d "$item" ]; then
      new_base="$(to_snake_component "$base")"
    elif [ -f "$item" ]; then
      new_base="$(normalize_file_name "$base")"
    else
      continue
    fi

    [ -n "$new_base" ] || continue
    if [ "$base" = "$new_base" ]; then
      continue
    fi

    candidate="$parent/$new_base"
    candidate_key="$(inode_key "$candidate")"
    old_key="$(inode_key "$item")"
    suffix=2
    while [ -n "$candidate_key" ] && [ "$candidate_key" != "$old_key" ]; do
      if [[ "$new_base" == *.* && "$item" == *.* && "$item" != .* ]]; then
        stem="${new_base%.*}"
        ext="${new_base##*.}"
        candidate="$parent/${stem}_${suffix}.${ext}"
      else
        candidate="$parent/${new_base}_${suffix}"
      fi
      candidate_key="$(inode_key "$candidate")"
      suffix=$((suffix + 1))
    done

    if [ "$item" = "$candidate" ]; then
      continue
    fi

    old_rel_item="${item#$SORTED_DIR_ABS/}"
    new_rel_item="${candidate#$SORTED_DIR_ABS/}"

    lower_old="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
    lower_new="$(printf '%s' "$(basename "$candidate")" | tr '[:upper:]' '[:lower:]')"
    if [ "$lower_old" = "$lower_new" ]; then
      temp_name="$parent/.rename_tmp_${RANDOM}_$$"
      mv "$item" "$temp_name"
      mv "$temp_name" "$candidate"
    else
      mv "$item" "$candidate"
    fi

    kind="file"
    if [ -d "$candidate" ]; then
      kind="dir"
    fi
    printf '%s\t%s\t%s\n' "$old_rel_item" "$new_rel_item" "$kind" >> "$FILE_REPORT"
    internal_rename_count=$((internal_rename_count + 1))

    if [ "$VERBOSE" -eq 1 ]; then
      echo "RENAMED $(upper_ascii "$kind"): $old_rel_item -> $new_rel_item"
    fi
  done < <(find "$project_abs" -depth -mindepth 1 \( -type d -o -type f \))
done < "$CANONICAL_MAP_FILE"

missing_shortcuts=""
while IFS="$FS" read -r _old_rel new_rel _target_new_rel _source_kind _target_kind; do
  [ -n "$new_rel" ] || continue
  link_abs="$SORTED_DIR_ABS/$new_rel"
  if [ ! -e "$link_abs" ] && [ ! -L "$link_abs" ]; then
    if [ -z "$missing_shortcuts" ]; then
      missing_shortcuts="$new_rel"
    else
      missing_shortcuts="${missing_shortcuts}"$'\n'"$new_rel"
    fi
  fi
done < "$SHORTCUT_MAP_FILE"

if [ -n "$missing_shortcuts" ]; then
  echo "Missing shortcuts detected after rename:" >&2
  echo "$missing_shortcuts" >&2
  exit 1
fi

broken_links="$(find "$SORTED_DIR_ABS" -mindepth 2 -maxdepth 2 -type l ! -exec test -e {} \; -print)"
if [ -n "$broken_links" ]; then
  echo "Broken links detected after rename:" >&2
  echo "$broken_links" >&2
  exit 1
fi

echo
echo "Apply complete."
echo "Project map report: $PROJECT_REPORT"
echo "File rename report: $FILE_REPORT"
echo "Internal file/dir renames applied: $internal_rename_count"
