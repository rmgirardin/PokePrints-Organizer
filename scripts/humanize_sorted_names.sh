#!/usr/bin/env bash

# If invoked via `sh script.sh`, re-exec under bash for compatibility.
# On macOS, /bin/sh is bash in POSIX mode and still sets BASH_VERSION.
if [ "${BASH##*/}" != "bash" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

usage() {
  cat <<'EOF'
Make internal project folders/files in Sorted by Pokemon easier to read.

Usage:
  humanize_sorted_names.sh [--sorted-dir <path>] [--dry-run|--apply] [--verbose]

Options:
  --sorted-dir <path>  Sorted root directory. Default: ./Sorted by Pokemon
  --dry-run            Plan only (default)
  --apply              Apply renames
  --verbose            Print every planned/applied rename
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

name_key() {
  normalize_phrase "$1" | tr -d ' '
}

normalize_phrase() {
  local raw="$1"
  perl -e '
    use strict;
    use warnings;
    my $s = shift // "";
    $s = lc $s;
    $s =~ s/\(variant\s+\d+\)//g;
    $s =~ s/&/ and /g;
    $s =~ s/[_\.\-]+/ /g;
    $s =~ s/\bgrooky\b/grookey/g;
    $s =~ s/\bscrobunny\b/scorbunny/g;
    $s =~ s/\bpipliup\b/piplup/g;
    $s =~ s/\bwobbebuffet\b/wobbuffet/g;
    $s =~ s/\bsmorelax\b/snorlax/g;
    $s =~ s/\bvaporon\b/vaporeon/g;
    $s =~ s/\bsleping\b/sleeping/g;
    $s =~ s/\bcolr\b/color/g;
    $s =~ s/\bclsy\b/clay/g;
    $s =~ s/\bpresup\b/presupported/g;
    $s =~ s/\bprintinplace\b/print in place/g;
    $s =~ s/[^a-z0-9 ]+/ /g;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    print $s;
  ' "$raw"
}

title_case_phrase() {
  local raw="$1"
  perl -e '
    use strict;
    use warnings;
    my $s = shift // "";
    my @w = grep { $_ ne "" } split / /, $s;
    my @out;
    for my $word (@w) {
      if ($word =~ /^\d+$/) {
        push @out, $word;
        next;
      }
      if ($word =~ /^v(\d+)$/) {
        push @out, "V$1";
        next;
      }
      if ($word eq "mmu") { push @out, "MMU"; next; }
      if ($word eq "fdm") { push @out, "FDM"; next; }
      if ($word eq "stl") { push @out, "STL"; next; }
      if ($word eq "chitubox") { push @out, "Chitubox"; next; }
      if ($word eq "presupported") { push @out, "Presupported"; next; }
      if ($word eq "pokeball") { push @out, "Pokeball"; next; }
      if ($word eq "gen") { push @out, "Gen"; next; }
      $word =~ s/^([a-z])/\U$1/;
      push @out, $word;
    }
    print join(" ", @out);
  ' "$raw"
}

strip_leading_noise() {
  local raw="$1"
  perl -e '
    use strict;
    use warnings;
    my $s = shift // "";
    my $changed = 1;
    while ($changed) {
      $changed = 0;
      if ($s =~ s/^(?:mpp|pres|presupported|april|august|january|february|march|may|june|july|september|october|november|december)\s+//) {
        $changed = 1;
      }
    }
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    print $s;
  ' "$raw"
}

strip_copy_token() {
  local raw="$1"
  perl -e '
    use strict;
    use warnings;
    my $s = shift // "";
    $s =~ s/\b(?:copy|copies|duplicate|dup|duplicated)\b//g;
    $s =~ s/\bcopy[ _-]*\d+\b//g;
    $s =~ s/\b(?:final|new|latest)\s+copy\b//g;
    $s =~ s/\bcopy\s*\([0-9]+\)\b//g;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    print $s;
  ' "$raw"
}

project_prefixes() {
  local project_name="$1"
  local p
  local alt

  p="$(normalize_phrase "$project_name")"
  [ -n "$p" ] && printf '%s\n' "$p"

  alt="$(printf '%s' "$p" | perl -pe 's/\bpokeball\b/ball/g')"
  if [ -n "$alt" ] && [ "$alt" != "$p" ]; then
    printf '%s\n' "$alt"
  fi

  alt="$(printf '%s' "$p" | perl -pe 's/\bball\b/pokeball/g')"
  if [ -n "$alt" ] && [ "$alt" != "$p" ]; then
    printf '%s\n' "$alt"
  fi
}

strip_project_prefix() {
  local phrase="$1"
  local project_name="$2"
  local current="$phrase"
  local prefix

  while IFS= read -r prefix; do
    [ -n "$prefix" ] || continue
    if [ "$current" = "$prefix" ]; then
      current=""
      continue
    fi
    if [[ "$current" == "$prefix "* ]]; then
      current="${current#"$prefix "}"
    fi
  done <<EOF
$(project_prefixes "$project_name" | awk '{print length, $0}' | sort -nr | cut -d' ' -f2-)
EOF

  printf '%s' "$current"
}

humanize_dir_name() {
  local phrase="$1"
  phrase="$(strip_copy_token "$phrase")"
  phrase="$(strip_leading_noise "$phrase")"
  case "$phrase" in
    "" )
      printf '%s' "Files"
      ;;
    "print"|"prints")
      printf '%s' "Print"
      ;;
    "presupported"|"presupported files")
      printf '%s' "Presupported"
      ;;
    "hinge in parts"|"hinge parts"|"hinge separated")
      printf '%s' "Hinge Parts"
      ;;
    "single material")
      printf '%s' "Single Material"
      ;;
    "multimaterial")
      printf '%s' "Multimaterial"
      ;;
    "resin")
      printf '%s' "Resin"
      ;;
    "fdm")
      printf '%s' "FDM"
      ;;
    "tamagotchi")
      printf '%s' "Tamagotchi"
      ;;
    * )
      title_case_phrase "$phrase"
      ;;
  esac
}

is_flatten_dir_name() {
  local raw_name="$1"
  local phrase
  phrase="$(normalize_phrase "$raw_name")"
  phrase="$(strip_copy_token "$phrase")"
  phrase="$(strip_leading_noise "$phrase")"

  case "$phrase" in
    "print"|"prints"|"image"|"images"|"file"|"files"|"model"|"models")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

humanize_file_name_stem() {
  local phrase="$1"
  local project_name="$2"
  local before_prefix
  local cleaned

  before_prefix="$(strip_copy_token "$phrase")"
  before_prefix="$(strip_leading_noise "$before_prefix")"

  cleaned="$before_prefix"
  cleaned="$(strip_project_prefix "$cleaned" "$project_name")"
  cleaned="$(strip_copy_token "$cleaned")"
  cleaned="$(strip_leading_noise "$cleaned")"

  if [ -z "$cleaned" ]; then
    cleaned="$before_prefix"
  fi
  if [[ "$cleaned" =~ ^[0-9]+$ ]]; then
    cleaned="model $cleaned"
  fi
  if [ -z "$cleaned" ]; then
    cleaned="model"
  fi

  title_case_phrase "$cleaned"
}

inode_key() {
  stat -f '%d:%i' "$1" 2>/dev/null || true
}

MODE="dry-run"
VERBOSE=0
SORTED_DIR="./Sorted by Pokemon"

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

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/humanize-sorted-names.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

PROJECTS_FILE="$TMP_DIR/projects.txt"
PLAN_FILE="$TMP_DIR/rename_plan.tsv"
FLATTEN_PLAN_FILE="$TMP_DIR/flatten_plan.tsv"
FS=$'\x1f'

find "$SORTED_DIR_ABS" -mindepth 2 -maxdepth 2 -type d | LC_ALL=C sort > "$PROJECTS_FILE"
: > "$PLAN_FILE"
: > "$FLATTEN_PLAN_FILE"

project_count=0
plan_count=0
flatten_plan_count=0

while IFS= read -r project_abs; do
  [ -n "$project_abs" ] || continue
  rel_project="${project_abs#$SORTED_DIR_ABS/}"
  pokemon="${rel_project%%/*}"
  [ "$pokemon" != "_reports" ] || continue
  [ "$pokemon" != "_photo_directory" ] || continue

  project_name="$(basename "$project_abs")"
  project_count=$((project_count + 1))

  while IFS= read -r item; do
    [ -n "$item" ] || continue
    parent="$(dirname "$item")"
    base="$(basename "$item")"
    kind="file"
    if [ -d "$item" ]; then
      kind="dir"
    fi

    stem="$base"
    ext=""
    if [ "$kind" = "file" ] && [[ "$base" == *.* && "$base" != .* ]]; then
      stem="${base%.*}"
      ext="${base##*.}"
    fi

    phrase="$(normalize_phrase "$stem")"
    stripped="$(strip_project_prefix "$phrase" "$project_name")"
    if [ -z "$stripped" ]; then
      stripped="$phrase"
    fi

    if [ "$kind" = "dir" ]; then
      new_base="$(humanize_dir_name "$stripped")"
    else
      new_stem="$(humanize_file_name_stem "$stripped" "$project_name")"
      if [ -n "$ext" ]; then
        ext_lower="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
        new_base="${new_stem}.${ext_lower}"
      else
        new_base="$new_stem"
      fi
    fi

    new_base="$(printf '%s' "$new_base" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    [ -n "$new_base" ] || continue

    candidate="$parent/$new_base"
    candidate_key="$(inode_key "$candidate")"
    old_key="$(inode_key "$item")"
    suffix=2

    while [ -n "$candidate_key" ] && [ "$candidate_key" != "$old_key" ]; do
      if [ "$kind" = "file" ] && [ -n "$ext" ]; then
        cstem="${new_base%.*}"
        cext="${new_base##*.}"
        candidate="$parent/${cstem} (${suffix}).${cext}"
      else
        candidate="$parent/${new_base} (${suffix})"
      fi
      candidate_key="$(inode_key "$candidate")"
      suffix=$((suffix + 1))
    done

    if [ "$candidate" != "$item" ]; then
      old_rel="${item#$SORTED_DIR_ABS/}"
      new_rel="${candidate#$SORTED_DIR_ABS/}"
      printf '%s%s%s%s%s%s%s\n' "$old_rel" "$FS" "$new_rel" "$FS" "$kind" "$FS" "$rel_project" >> "$PLAN_FILE"
      plan_count=$((plan_count + 1))
    fi

    if [ "$kind" = "dir" ]; then
      candidate_rel="${candidate#$SORTED_DIR_ABS/}"
      candidate_base="$(basename "$candidate")"
      if is_flatten_dir_name "$candidate_base"; then
        printf '%s%s%s\n' "$candidate_rel" "$FS" "$rel_project" >> "$FLATTEN_PLAN_FILE"
        flatten_plan_count=$((flatten_plan_count + 1))
      fi
    fi
  done < <(find "$project_abs" -depth -mindepth 1 \( -type d -o -type f \))
done < "$PROJECTS_FILE"

echo "Sorted directory: $SORTED_DIR_ABS"
echo "Mode: $MODE"
echo "Projects scanned: $project_count"
echo "Planned internal renames: $plan_count"
echo "Planned generic-folder flatten operations: $flatten_plan_count"

if [ "$VERBOSE" -eq 1 ]; then
  echo
  awk -F "$FS" '{printf "PLAN %s: %s -> %s\n", toupper($3), $1, $2}' "$PLAN_FILE"
  if [ "$flatten_plan_count" -gt 0 ]; then
    echo
    awk -F "$FS" '{printf "PLAN FLATTEN: %s\n", $1}' "$FLATTEN_PLAN_FILE" | LC_ALL=C sort -u
  fi
elif [ "$MODE" = "dry-run" ]; then
  echo
  echo "Preview (first 120 planned renames):"
  awk -F "$FS" '{printf "PLAN %s: %s -> %s\n", toupper($3), $1, $2}' "$PLAN_FILE" | sed -n '1,120p'
  if [ "$plan_count" -gt 120 ]; then
    echo "... ($((plan_count - 120)) more planned renames; use --verbose to list all)"
  fi
  if [ "$flatten_plan_count" -gt 0 ]; then
    echo
    echo "Preview flatten dirs (first 60):"
    awk -F "$FS" '{printf "PLAN FLATTEN: %s\n", $1}' "$FLATTEN_PLAN_FILE" | LC_ALL=C sort -u | sed -n '1,60p'
  fi
fi

if [ "$MODE" = "dry-run" ]; then
  exit 0
fi

REPORT_FILE="$SORTED_DIR_ABS/_reports/name_humanize_internal_renames.tsv"
printf 'old_path\tnew_path\tkind\tproject\n' > "$REPORT_FILE"

applied_count=0
while IFS="$FS" read -r old_rel new_rel kind project_rel; do
  [ -n "$old_rel" ] || continue
  old_abs="$SORTED_DIR_ABS/$old_rel"
  new_abs="$SORTED_DIR_ABS/$new_rel"
  [ -e "$old_abs" ] || err "Path missing before rename: $old_abs"

  mkdir -p "$(dirname "$new_abs")"

  lower_old="$(printf '%s' "$(basename "$old_abs")" | tr '[:upper:]' '[:lower:]')"
  lower_new="$(printf '%s' "$(basename "$new_abs")" | tr '[:upper:]' '[:lower:]')"
  if [ "$lower_old" = "$lower_new" ]; then
    temp="$(dirname "$old_abs")/.rename_tmp_${RANDOM}_$$"
    mv "$old_abs" "$temp"
    mv "$temp" "$new_abs"
  else
    mv "$old_abs" "$new_abs"
  fi

  printf '%s\t%s\t%s\t%s\n' "$old_rel" "$new_rel" "$kind" "$project_rel" >> "$REPORT_FILE"
  applied_count=$((applied_count + 1))

  if [ "$VERBOSE" -eq 1 ]; then
    echo "RENAMED $(upper_ascii "$kind"): $old_rel -> $new_rel"
  fi
done < "$PLAN_FILE"

flatten_move_count=0
flatten_dir_removed_count=0
while IFS= read -r project_abs; do
  [ -n "$project_abs" ] || continue
  rel_project="${project_abs#$SORTED_DIR_ABS/}"
  pokemon="${rel_project%%/*}"
  [ "$pokemon" != "_reports" ] || continue
  [ -d "$project_abs" ] || continue

  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    while IFS= read -r flatten_dir; do
      [ -n "$flatten_dir" ] || continue
      [ -d "$flatten_dir" ] || continue
      flatten_base="$(basename "$flatten_dir")"
      if ! is_flatten_dir_name "$flatten_base"; then
        continue
      fi

      parent_dir="$(dirname "$flatten_dir")"
      while IFS= read -r child; do
        [ -n "$child" ] || continue
        [ -e "$child" ] || [ -L "$child" ] || continue
        child_base="$(basename "$child")"
        target="$parent_dir/$child_base"
        suffix=2
        while [ -e "$target" ] || [ -L "$target" ]; do
          if [ -f "$child" ] && [[ "$child_base" == *.* && "$child_base" != .* ]]; then
            stem="${child_base%.*}"
            ext="${child_base##*.}"
            target="$parent_dir/${stem} (${suffix}).${ext}"
          else
            target="$parent_dir/${child_base} (${suffix})"
          fi
          suffix=$((suffix + 1))
        done

        old_rel="${child#$SORTED_DIR_ABS/}"
        new_rel="${target#$SORTED_DIR_ABS/}"
        mv "$child" "$target"
        moved_kind="file"
        if [ -d "$target" ]; then
          moved_kind="dir"
        fi
        printf '%s\t%s\t%s\t%s\n' "$old_rel" "$new_rel" "flatten_${moved_kind}" "$rel_project" >> "$REPORT_FILE"
        flatten_move_count=$((flatten_move_count + 1))

        if [ "$VERBOSE" -eq 1 ]; then
          echo "FLATTEN $(upper_ascii "$moved_kind"): $old_rel -> $new_rel"
        fi
      done < <(find "$flatten_dir" -mindepth 1 -maxdepth 1 | LC_ALL=C sort)

      if rmdir "$flatten_dir" 2>/dev/null; then
        flatten_dir_removed_count=$((flatten_dir_removed_count + 1))
        changed=1
        if [ "$VERBOSE" -eq 1 ]; then
          echo "REMOVED FLATTEN DIR: ${flatten_dir#$SORTED_DIR_ABS/}"
        fi
      fi
    done < <(find "$project_abs" -mindepth 1 -type d -depth | LC_ALL=C sort)
  done
done < "$PROJECTS_FILE"

redundant_project_move_count=0
redundant_project_flatten_count=0
while IFS= read -r pokemon_dir; do
  [ -n "$pokemon_dir" ] || continue
  [ -d "$pokemon_dir" ] || continue
  pokemon_name="$(basename "$pokemon_dir")"
  case "$pokemon_name" in
    _reports|_photo_directory)
      continue
      ;;
  esac

  dir_children="$(find "$pokemon_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  if [ "$dir_children" -ne 1 ]; then
    continue
  fi

  child_dir="$(find "$pokemon_dir" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')"
  [ -n "$child_dir" ] || continue
  child_base="$(basename "$child_dir")"
  if [ "$(name_key "$pokemon_name")" != "$(name_key "$child_base")" ]; then
    continue
  fi

  while IFS= read -r child; do
    [ -n "$child" ] || continue
    [ -e "$child" ] || [ -L "$child" ] || continue
    item_base="$(basename "$child")"
    target="$pokemon_dir/$item_base"
    suffix=2
    while [ -e "$target" ] || [ -L "$target" ]; do
      if [ -f "$child" ] && [[ "$item_base" == *.* && "$item_base" != .* ]]; then
        stem="${item_base%.*}"
        ext="${item_base##*.}"
        target="$pokemon_dir/${stem} (${suffix}).${ext}"
      else
        target="$pokemon_dir/${item_base} (${suffix})"
      fi
      suffix=$((suffix + 1))
    done

    old_rel="${child#$SORTED_DIR_ABS/}"
    new_rel="${target#$SORTED_DIR_ABS/}"
    mv "$child" "$target"
    moved_kind="file"
    if [ -d "$target" ]; then
      moved_kind="dir"
    fi
    printf '%s\t%s\t%s\t%s\n' "$old_rel" "$new_rel" "flatten_redundant_${moved_kind}" "$pokemon_name" >> "$REPORT_FILE"
    redundant_project_move_count=$((redundant_project_move_count + 1))
    if [ "$VERBOSE" -eq 1 ]; then
      echo "FLATTEN REDUNDANT $(upper_ascii "$moved_kind"): $old_rel -> $new_rel"
    fi
  done < <(find "$child_dir" -mindepth 1 -maxdepth 1 | LC_ALL=C sort)

  if rmdir "$child_dir" 2>/dev/null; then
    redundant_project_flatten_count=$((redundant_project_flatten_count + 1))
    if [ "$VERBOSE" -eq 1 ]; then
      echo "REMOVED REDUNDANT PROJECT DIR: ${child_dir#$SORTED_DIR_ABS/}"
    fi
  fi
done < <(find "$SORTED_DIR_ABS" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)

nested_pokemon_move_count=0
nested_pokemon_dir_removed_count=0
while IFS= read -r project_abs; do
  [ -n "$project_abs" ] || continue
  rel_project="${project_abs#$SORTED_DIR_ABS/}"
  pokemon="${rel_project%%/*}"
  [ "$pokemon" != "_reports" ] || continue
  [ "$pokemon" != "_photo_directory" ] || continue
  [ -d "$project_abs" ] || continue

  pokemon_key="$(name_key "$pokemon")"
  pokemon_phrase="$(normalize_phrase "$pokemon")"
  [ -n "$pokemon_key" ] || continue
  [ -n "$pokemon_phrase" ] || continue

  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    while IFS= read -r nested_dir; do
      [ -n "$nested_dir" ] || continue
      [ -d "$nested_dir" ] || continue

      nested_base="$(basename "$nested_dir")"
      if [ "$(name_key "$nested_base")" != "$pokemon_key" ]; then
        continue
      fi

      parent_dir="$(dirname "$nested_dir")"
      parent_base="$(basename "$parent_dir")"
      parent_phrase="$(normalize_phrase "$parent_base")"
      if [[ " $parent_phrase " != *" $pokemon_phrase "* ]]; then
        continue
      fi

      while IFS= read -r child; do
        [ -n "$child" ] || continue
        [ -e "$child" ] || [ -L "$child" ] || continue
        item_base="$(basename "$child")"
        target="$parent_dir/$item_base"
        suffix=2
        while [ -e "$target" ] || [ -L "$target" ]; do
          if [ -f "$child" ] && [[ "$item_base" == *.* && "$item_base" != .* ]]; then
            stem="${item_base%.*}"
            ext="${item_base##*.}"
            target="$parent_dir/${stem} (${suffix}).${ext}"
          else
            target="$parent_dir/${item_base} (${suffix})"
          fi
          suffix=$((suffix + 1))
        done

        old_rel="${child#$SORTED_DIR_ABS/}"
        new_rel="${target#$SORTED_DIR_ABS/}"
        mv "$child" "$target"
        moved_kind="file"
        if [ -d "$target" ]; then
          moved_kind="dir"
        fi
        printf '%s\t%s\t%s\t%s\n' "$old_rel" "$new_rel" "flatten_nested_pokemon_${moved_kind}" "$rel_project" >> "$REPORT_FILE"
        nested_pokemon_move_count=$((nested_pokemon_move_count + 1))
        if [ "$VERBOSE" -eq 1 ]; then
          echo "FLATTEN NESTED POKEMON $(upper_ascii "$moved_kind"): $old_rel -> $new_rel"
        fi
      done < <(find "$nested_dir" -mindepth 1 -maxdepth 1 | LC_ALL=C sort)

      if rmdir "$nested_dir" 2>/dev/null; then
        nested_pokemon_dir_removed_count=$((nested_pokemon_dir_removed_count + 1))
        changed=1
        if [ "$VERBOSE" -eq 1 ]; then
          echo "REMOVED NESTED POKEMON DIR: ${nested_dir#$SORTED_DIR_ABS/}"
        fi
      fi
    done < <(find "$project_abs" -mindepth 1 -type d -depth | LC_ALL=C sort)
  done
done < "$PROJECTS_FILE"

broken_links="$(find "$SORTED_DIR_ABS" -mindepth 2 -maxdepth 2 -type l ! -exec test -e {} \; -print)"
if [ -n "$broken_links" ]; then
  echo "Broken project links detected after rename:" >&2
  echo "$broken_links" >&2
  exit 1
fi

echo
echo "Apply complete."
echo "Applied internal renames: $applied_count"
echo "Flatten moves applied: $flatten_move_count"
echo "Flatten dirs removed: $flatten_dir_removed_count"
echo "Redundant project flatten moves: $redundant_project_move_count"
echo "Redundant project dirs removed: $redundant_project_flatten_count"
echo "Nested pokemon flatten moves: $nested_pokemon_move_count"
echo "Nested pokemon dirs removed: $nested_pokemon_dir_removed_count"
echo "Report: $REPORT_FILE"
