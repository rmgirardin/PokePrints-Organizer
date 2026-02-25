#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Sort Pokemon model projects into Pokemon-centric folders.

Usage:
  sort_pokemon_models.sh [--base-dir <path>] [--output-dir <name>] [--output-root <path>] [--dry-run|--apply] [--move|--copy|--transfer-mode <move|copy>] [--shortcut-type <alias|symlink>] [--verbose]

Options:
  --base-dir <path>   Base directory to scan. Default: current directory
  --output-dir <name> Output folder name inside base dir. Default: Sorted by Pokemon
  --output-root <path> Absolute/relative output root path. Overrides --output-dir
  --dry-run           Plan only (default); no filesystem writes
  --apply             Perform transfer + shortcut operations and write manifest
  --move              Use move mode for canonical projects (default)
  --copy              Use copy mode for canonical projects
  --transfer-mode     Set transfer mode explicitly: move or copy
  --shortcut-type     Shortcut type for multi-Pokemon references: alias or symlink (default: alias)
  --alias-shortcuts   Use macOS Finder aliases for multi-Pokemon references (default)
  --symlink-shortcuts Use symbolic links for multi-Pokemon references
  --verbose           Print additional diagnostics
  -h, --help          Show this help
EOF
}

err() {
  echo "Error: $*" >&2
  exit 1
}

trim_trailing_spaces() {
  printf '%s' "$1" | sed 's/[[:space:]]*$//'
}

normalize_for_match() {
  perl -e '
    use strict;
    use warnings;
    use utf8;
    use Unicode::Normalize qw(NFKD);
    my $s = @ARGV ? shift : do { local $/; <STDIN> // "" };
    $s = NFKD($s);
    $s =~ s/\pM//g;
    $s = lc $s;
    $s =~ s/nidoran[♀]/nidoran-f/g;
    $s =~ s/nidoran[♂]/nidoran-m/g;
    $s =~ s/type:/type/g;
    $s =~ s/mr\./mr/g;
    $s =~ s/jr\./jr/g;
    $s =~ s/sirfetch'\''d/sirfetchd/g;
    $s =~ s/[^a-z0-9]+/ /g;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    print $s;
  ' "$1"
}

normalize_token_stream() {
  perl -e '
    use strict;
    use warnings;
    use utf8;
    use Unicode::Normalize qw(NFKD);
    my $s = @ARGV ? shift : do { local $/; <STDIN> // "" };
    $s = NFKD($s);
    $s =~ s/\pM//g;
    $s = lc $s;
    $s =~ s/nidoran[♀]/nidoran-f/g;
    $s =~ s/nidoran[♂]/nidoran-m/g;
    $s =~ s/type:/type/g;
    $s =~ s/mr\./mr/g;
    $s =~ s/jr\./jr/g;
    $s =~ s/sirfetch'\''d/sirfetchd/g;
    $s =~ s/[^a-z0-9\- ]+/ /g;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;
    print $s;
  ' "$1"
}

title_case_words() {
  perl -e '
    use strict;
    use warnings;
    my $s = shift // "";
    my @words = grep { $_ ne "" } split / /, lc $s;
    my @out;
    for my $w (@words) {
      if ($w =~ /^\d+$/) {
        push @out, $w;
        next;
      }
      if ($w eq "mr") {
        push @out, "Mr";
        next;
      }
      if ($w eq "jr") {
        push @out, "Jr";
        next;
      }
      if ($w eq "type") {
        push @out, "Type";
        next;
      }
      $w =~ s/^([a-z])/\U$1/;
      push @out, $w;
    }
    print join(" ", @out);
  ' "$1"
}

display_name_from_raw() {
  perl -e '
    use strict;
    use warnings;
    my $s = shift // "";
    $s = lc $s;
    $s =~ s/\s+/ /g;
    $s =~ s/^\s+|\s+$//g;

    my %special = (
      "farfetchd" => "Farfetchd",
      "sirfetchd" => "Sirfetchd",
      "mr mime" => "Mr Mime",
      "mr rime" => "Mr Rime",
      "mime jr" => "Mime Jr",
      "type null" => "Type Null",
      "nidoran-f" => "Nidoran-F",
      "nidoran-m" => "Nidoran-M",
    );
    if (exists $special{$s}) {
      print $special{$s};
      exit 0;
    }

    my @out_words;
    for my $word (split / /, $s) {
      next if $word eq "";
      my @parts = split /-/, $word;
      my @out_parts;
      for my $part (@parts) {
        if ($part eq "mr") {
          push @out_parts, "Mr";
          next;
        }
        if ($part eq "jr") {
          push @out_parts, "Jr";
          next;
        }
        if ($part =~ /^\d+$/) {
          push @out_parts, $part;
          next;
        }
        $part =~ s/^([a-z])/\U$1/;
        push @out_parts, $part;
      }
      push @out_words, join("-", @out_parts);
    }
    print join(" ", @out_words);
  ' "$1"
}

build_pokedex_catalog() {
  local out_file="$1"
  local token_stream_file="$2"
  local aliases_file="$3"
  local normalized_stream
  local species_tmp
  local parsed_count

  [ -f "$token_stream_file" ] || err "Missing Pokedex token stream file: $token_stream_file"
  species_tmp="$TMP_DIR/pokedex_species_raw.txt"
  : > "$species_tmp"

  normalized_stream="$(normalize_token_stream "$(cat "$token_stream_file")")"
  read -r -a tokens <<< "$normalized_stream"

  local i=0
  local token_count="${#tokens[@]}"
  local current
  local next
  local species

  while [ "$i" -lt "$token_count" ]; do
    current="${tokens[$i]}"
    next=""
    if [ $((i + 1)) -lt "$token_count" ]; then
      next="${tokens[$((i + 1))]}"
    fi
    species="$current"

    case "$current" in
      mr)
        case "$next" in
          mime|rime)
            species="mr $next"
            i=$((i + 2))
            ;;
          *)
            i=$((i + 1))
            ;;
        esac
        ;;
      mime)
        if [ "$next" = "jr" ]; then
          species="mime jr"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      type)
        if [ "$next" = "null" ]; then
          species="type null"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      tapu)
        case "$next" in
          koko|lele|bulu|fini)
            species="tapu $next"
            i=$((i + 2))
            ;;
          *)
            i=$((i + 1))
            ;;
        esac
        ;;
      great)
        if [ "$next" = "tusk" ]; then
          species="great tusk"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      scream)
        if [ "$next" = "tail" ]; then
          species="scream tail"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      brute)
        if [ "$next" = "bonnet" ]; then
          species="brute bonnet"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      flutter)
        if [ "$next" = "mane" ]; then
          species="flutter mane"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      slither)
        if [ "$next" = "wing" ]; then
          species="slither wing"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      sandy)
        if [ "$next" = "shocks" ]; then
          species="sandy shocks"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      iron)
        case "$next" in
          treads|bundle|hands|jugulis|moth|thorns|valiant|leaves|boulder|crown)
            species="iron $next"
            i=$((i + 2))
            ;;
          *)
            i=$((i + 1))
            ;;
        esac
        ;;
      roaring)
        if [ "$next" = "moon" ]; then
          species="roaring moon"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      walking)
        if [ "$next" = "wake" ]; then
          species="walking wake"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      gouging)
        if [ "$next" = "fire" ]; then
          species="gouging fire"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      raging)
        if [ "$next" = "bolt" ]; then
          species="raging bolt"
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      *)
        i=$((i + 1))
        ;;
    esac

    printf '%s\n' "$species" >> "$species_tmp"
  done

  parsed_count="$(awk '!seen[$0]++ {count++} END {print count+0}' "$species_tmp")"
  if [ "$parsed_count" -lt 900 ]; then
    err "Parsed too few Pokemon species from token stream ($parsed_count)."
  fi

  : > "$out_file"
  awk '!seen[$0]++ {print $0}' "$species_tmp" | while IFS= read -r raw_name; do
    [ -n "$raw_name" ] || continue
    normalized_name="$(normalize_for_match "$raw_name")"
    display_name="$(display_name_from_raw "$raw_name")"
    printf '%s\t%s\n' "$normalized_name" "$display_name" >> "$out_file"
  done

  if [ -f "$aliases_file" ]; then
    while IFS=$'\t' read -r alias_name canonical_name; do
      [ -n "$alias_name" ] || continue
      case "$alias_name" in
        \#*)
          continue
          ;;
      esac
      alias_normalized="$(normalize_for_match "$alias_name")"
      [ -n "$alias_normalized" ] || continue
      if [ -z "$canonical_name" ]; then
        canonical_name="$(title_case_words "$alias_normalized")"
      fi
      printf '%s\t%s\n' "$alias_normalized" "$canonical_name" >> "$out_file"
    done < "$aliases_file"
  fi

  awk -F $'\t' '!seen[$1]++ {print $0}' "$out_file" > "${out_file}.tmp"
  mv "${out_file}.tmp" "$out_file"
}

detect_pokemon_list() {
  local source_abs="$1"
  local project_name_trimmed="$2"
  local raw_text
  local text
  local matches_file
  local normalized_name
  local display_name
  local keep
  local other_normalized
  local _other_display

  # Project override map.
  if [ "$project_name_trimmed" = "Gen 4 Statue" ]; then
    printf '%s\n' "Chimchar" "Piplup" "Turtwig"
    return
  fi

  raw_text="$(
    {
      printf '%s\n' "$project_name_trimmed"
      find "$source_abs" -mindepth 1 -type d -print | sed 's#^.*/##'
      find "$source_abs" -type f \( -iname '*.stl' -o -iname '*.3mf' -o -iname '*.chitubox' \) -print | sed 's#^.*/##'
    }
  )"
  text="$(normalize_for_match "$raw_text")"
  text=" $text "
  matches_file="$TMP_DIR/detected_matches_$$.tsv"
  : > "$matches_file"

  while IFS=$'\t' read -r normalized_name display_name; do
    [ -n "$normalized_name" ] || continue
    case "$text" in
      *" $normalized_name "*)
        printf '%s\t%s\n' "$normalized_name" "$display_name" >> "$matches_file"
        ;;
    esac
  done < "$POKEDEX_CATALOG_FILE"

  if [ ! -s "$matches_file" ]; then
    return
  fi

  while IFS=$'\t' read -r normalized_name display_name; do
    [ -n "$normalized_name" ] || continue
    keep=1
    while IFS=$'\t' read -r other_normalized _other_display; do
      [ -n "$other_normalized" ] || continue
      if [ "$normalized_name" = "$other_normalized" ]; then
        continue
      fi
      case " $other_normalized " in
        *" $normalized_name "*)
          keep=0
          break
          ;;
      esac
    done < "$matches_file"
    if [ "$keep" -eq 1 ]; then
      printf '%s\n' "$display_name"
    fi
  done < "$matches_file" | LC_ALL=C sort -u
}

relative_path() {
  local from_dir="$1"
  local to_path="$2"
  perl -MFile::Spec -e 'print File::Spec->abs2rel($ARGV[1], $ARGV[0])' "$from_dir" "$to_path"
}

to_abs_path() {
  perl -MFile::Spec -e 'print File::Spec->rel2abs($ARGV[0])' "$1"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
POKEDEX_TOKEN_STREAM_FILE="$DATA_DIR/pokedex_token_stream.txt"
POKEMON_ALIASES_FILE="$DATA_DIR/pokemon_aliases.tsv"
POKEDEX_CATALOG_FILE=""

BASE_DIR="."
OUTPUT_DIR_NAME="Sorted by Pokemon"
OUTPUT_ROOT_OVERRIDE=""
MODE="dry-run"
TRANSFER_MODE="move"
SHORTCUT_TYPE="alias"
VERBOSE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-dir)
      shift
      [ "$#" -gt 0 ] || err "--base-dir requires a value"
      BASE_DIR="$1"
      ;;
    --output-dir)
      shift
      [ "$#" -gt 0 ] || err "--output-dir requires a value"
      OUTPUT_DIR_NAME="$1"
      ;;
    --output-root)
      shift
      [ "$#" -gt 0 ] || err "--output-root requires a value"
      OUTPUT_ROOT_OVERRIDE="$1"
      ;;
    --dry-run)
      MODE="dry-run"
      ;;
    --apply)
      MODE="apply"
      ;;
    --move)
      TRANSFER_MODE="move"
      ;;
    --copy)
      TRANSFER_MODE="copy"
      ;;
    --transfer-mode)
      shift
      [ "$#" -gt 0 ] || err "--transfer-mode requires a value"
      case "$1" in
        move|copy)
          TRANSFER_MODE="$1"
          ;;
        *)
          err "--transfer-mode must be 'move' or 'copy'"
          ;;
      esac
      ;;
    --shortcut-type)
      shift
      [ "$#" -gt 0 ] || err "--shortcut-type requires a value"
      case "$1" in
        alias|symlink)
          SHORTCUT_TYPE="$1"
          ;;
        *)
          err "--shortcut-type must be 'alias' or 'symlink'"
          ;;
      esac
      ;;
    --alias-shortcuts)
      SHORTCUT_TYPE="alias"
      ;;
    --symlink-shortcuts)
      SHORTCUT_TYPE="symlink"
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

if [ "$SHORTCUT_TYPE" = "alias" ]; then
  SHORTCUT_PLAN_LABEL="ALIAS"
  SHORTCUT_SUMMARY_LABEL="Finder alias shortcuts"
  SHORTCUT_STATUS_SUFFIX="aliased"
else
  SHORTCUT_PLAN_LABEL="LINK"
  SHORTCUT_SUMMARY_LABEL="Symlink shortcuts"
  SHORTCUT_STATUS_SUFFIX="linked"
fi

[ -d "$BASE_DIR" ] || err "Base directory not found: $BASE_DIR"
BASE_DIR_ABS="$(cd "$BASE_DIR" && pwd)"
if [ -n "$OUTPUT_ROOT_OVERRIDE" ]; then
  OUTPUT_ROOT="$(to_abs_path "$OUTPUT_ROOT_OVERRIDE")"
else
  OUTPUT_ROOT="$BASE_DIR_ABS/$OUTPUT_DIR_NAME"
fi

OUTPUT_TOP_EXCLUDE=""
if [[ "$OUTPUT_ROOT" == "$BASE_DIR_ABS"/* ]]; then
  output_rel="${OUTPUT_ROOT#$BASE_DIR_ABS/}"
  if [ -n "$output_rel" ] && [[ "$output_rel" != */* ]]; then
    OUTPUT_TOP_EXCLUDE="$output_rel"
  fi
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sort-pokemon-models.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
FIELD_SEP=$'\x1f'
LINK_SEP=$'\x1e'

PROJECTS_ALL_FILE="$TMP_DIR/projects_all.txt"
PROJECTS_FILE="$TMP_DIR/projects.txt"
RECORDS_FILE="$TMP_DIR/records.tsv"
DEST_MAP_FILE="$TMP_DIR/destinations.tsv"
USED_DESTS_FILE="$TMP_DIR/used_destinations.txt"
MANIFEST_PREVIEW_FILE="$TMP_DIR/manifest_preview.tsv"
POKEDEX_CATALOG_FILE="$TMP_DIR/pokedex_catalog.tsv"

build_pokedex_catalog "$POKEDEX_CATALOG_FILE" "$POKEDEX_TOKEN_STREAM_FILE" "$POKEMON_ALIASES_FILE"

find "$BASE_DIR_ABS" -mindepth 2 -maxdepth 2 -type d | LC_ALL=C sort > "$PROJECTS_ALL_FILE"

: > "$PROJECTS_FILE"
while IFS= read -r project_abs; do
  [ -n "$project_abs" ] || continue
  rel="${project_abs#$BASE_DIR_ABS/}"
  [ "$rel" != "$project_abs" ] || continue
  top="${rel%%/*}"
  if [ -n "$OUTPUT_TOP_EXCLUDE" ] && [ "$top" = "$OUTPUT_TOP_EXCLUDE" ]; then
    continue
  fi
  case "$top" in
    scripts|Sorted\ by\ Pokemon*)
      continue
      ;;
  esac
  printf '%s\n' "$project_abs" >> "$PROJECTS_FILE"
done < "$PROJECTS_ALL_FILE"

source_count=0
link_count=0
unmapped_count=0
auto_collision_resolved_count=0

: > "$RECORDS_FILE"
: > "$DEST_MAP_FILE"
: > "$USED_DESTS_FILE"
printf 'source_project\tdetected_pokemon_csv\tprimary_pokemon\tcanonical_dest\tlink_dests_csv\tstatus\n' > "$MANIFEST_PREVIEW_FILE"

existing_dest_count=0
if [ -d "$OUTPUT_ROOT" ]; then
  while IFS= read -r existing_abs; do
    [ -n "$existing_abs" ] || continue
    existing_rel="${existing_abs#$OUTPUT_ROOT/}"
    [ "$existing_rel" != "$existing_abs" ] || continue
    existing_top="${existing_rel%%/*}"
    [ "$existing_top" != "_reports" ] || continue
    printf '%s\n' "$existing_rel" >> "$USED_DESTS_FILE"
    existing_dest_count=$((existing_dest_count + 1))
  done < <(find "$OUTPUT_ROOT" -mindepth 2 -maxdepth 2 \( -type d -o -type l -o -type f \) | LC_ALL=C sort)
fi

while IFS= read -r source_abs; do
  [ -n "$source_abs" ] || continue

  source_rel="${source_abs#$BASE_DIR_ABS/}"
  month_name="${source_rel%%/*}"
  project_name_raw="${source_rel#*/}"
  project_name_trimmed="$(trim_trailing_spaces "$project_name_raw")"
  base_folder_name="${month_name} - ${project_name_trimmed}"
  folder_name="$base_folder_name"

  detected_list="$(detect_pokemon_list "$source_abs" "$project_name_trimmed")"
  detected_csv="$(printf '%s\n' "$detected_list" | sed '/^$/d' | paste -sd, -)"

  target_pokemon_list=""
  secondaries=""
  if [ -z "$detected_csv" ]; then
    primary="_Unmapped"
    target_pokemon_list="$primary"
    unmapped_count=$((unmapped_count + 1))
  else
    primary="$(printf '%s\n' "$detected_list" | sed -n '1p')"
    target_pokemon_list="$primary"
    secondaries="$(printf '%s\n' "$detected_list" | sed '1d')"
    while IFS= read -r secondary; do
      [ -n "$secondary" ] || continue
      target_pokemon_list="${target_pokemon_list}"$'\n'"$secondary"
    done <<EOF
$secondaries
EOF
  fi

  variant_num=2
  while :; do
    has_collision=0
    while IFS= read -r target_pokemon; do
      [ -n "$target_pokemon" ] || continue
      candidate_dest="${target_pokemon}/${folder_name}"
      if grep -Fqx "$candidate_dest" "$USED_DESTS_FILE"; then
        has_collision=1
        break
      fi
    done <<EOF
$target_pokemon_list
EOF
    if [ "$has_collision" -eq 0 ]; then
      break
    fi
    folder_name="${base_folder_name} (Variant ${variant_num})"
    variant_num=$((variant_num + 1))
  done

  if [ "$folder_name" != "$base_folder_name" ]; then
    auto_collision_resolved_count=$((auto_collision_resolved_count + 1))
    if [ "$VERBOSE" -eq 1 ]; then
      echo "AUTO-RESOLVE COLLISION: $source_rel -> $folder_name"
    fi
  fi

  if [ -z "$detected_csv" ]; then
    canonical_dest="_Unmapped/${folder_name}"
    link_list=""
    link_csv_display=""
  else
    canonical_dest="${primary}/${folder_name}"
    link_list=""
    link_csv_display=""
    while IFS= read -r secondary; do
      [ -n "$secondary" ] || continue
      link_dest="${secondary}/${folder_name}"
      if [ -z "$link_list" ]; then
        link_list="$link_dest"
      else
        link_list="${link_list}${LINK_SEP}${link_dest}"
      fi
      if [ -z "$link_csv_display" ]; then
        link_csv_display="$link_dest"
      else
        link_csv_display="${link_csv_display},${link_dest}"
      fi
      link_count=$((link_count + 1))
    done <<EOF
$secondaries
EOF
  fi

  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
    "$source_abs" \
    "$source_rel" \
    "$detected_csv" \
    "$primary" \
    "$canonical_dest" \
    "$link_list" >> "$RECORDS_FILE"

  printf '%s%s%s\n' "$canonical_dest" "$FIELD_SEP" "$source_rel" >> "$DEST_MAP_FILE"
  printf '%s\n' "$canonical_dest" >> "$USED_DESTS_FILE"
  if [ -n "$link_list" ]; then
    while IFS= read -r link_dest; do
      [ -n "$link_dest" ] || continue
      printf '%s%s%s\n' "$link_dest" "$FIELD_SEP" "$source_rel" >> "$DEST_MAP_FILE"
      printf '%s\n' "$link_dest" >> "$USED_DESTS_FILE"
    done <<EOF
$(printf '%s' "$link_list" | perl -0pe 's/\x1e/\n/g')
EOF
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$source_rel" \
    "$detected_csv" \
    "$primary" \
    "$canonical_dest" \
    "$link_csv_display" \
    "planned" >> "$MANIFEST_PREVIEW_FILE"

  source_count=$((source_count + 1))
done < "$PROJECTS_FILE"

dup_paths_file="$TMP_DIR/duplicate_destinations.txt"
awk -F "$FIELD_SEP" '{print $1}' "$DEST_MAP_FILE" | LC_ALL=C sort | uniq -d > "$dup_paths_file"
if [ -s "$dup_paths_file" ]; then
  echo "Destination path collisions detected:" >&2
  while IFS= read -r dup_dest; do
    [ -n "$dup_dest" ] || continue
    echo "  $dup_dest" >&2
    awk -F "$FIELD_SEP" -v d="$dup_dest" '$1 == d {printf "    <- %s\n", $2}' "$DEST_MAP_FILE" >&2
  done < "$dup_paths_file"
  exit 1
fi

pokemon_folder_count="$(
  awk -F "$FIELD_SEP" '{print $1}' "$DEST_MAP_FILE" | cut -d'/' -f1 | LC_ALL=C sort -u | awk '$0 != "_Unmapped" {count++} END {print count+0}'
)"

echo "Base directory: $BASE_DIR_ABS"
echo "Mode: $MODE"
echo "Transfer mode: $TRANSFER_MODE"
echo "Shortcut type: $SHORTCUT_TYPE"
echo "Output directory: $OUTPUT_ROOT"
echo "Discovered source projects: $source_count"
echo "Planned canonical transfers: $source_count"
echo "Planned ${SHORTCUT_SUMMARY_LABEL}: $link_count"
echo "Existing destination entries: $existing_dest_count"
echo "Auto-resolved destination collisions: $auto_collision_resolved_count"
echo "Pokemon folders (excluding _Unmapped): $pokemon_folder_count"
echo "Unmapped projects: $unmapped_count"

if [ "$VERBOSE" -eq 1 ]; then
  echo
  echo "Manifest preview:"
  cat "$MANIFEST_PREVIEW_FILE"
  echo
fi

if [ "$MODE" = "dry-run" ]; then
  echo
  echo "Planned actions:"
  transfer_label="$(printf '%s' "$TRANSFER_MODE" | tr '[:lower:]' '[:upper:]')"
  while IFS="$FIELD_SEP" read -r _source_abs source_rel _detected_csv _primary canonical_dest link_list; do
    [ -n "$source_rel" ] || continue
    echo "PLAN ${transfer_label}: $source_rel -> $canonical_dest"
    if [ -n "$link_list" ]; then
      while IFS= read -r link_dest; do
        [ -n "$link_dest" ] || continue
        echo "PLAN ${SHORTCUT_PLAN_LABEL}: $link_dest -> $canonical_dest"
      done <<EOF
$(printf '%s' "$link_list" | perl -0pe 's/\x1e/\n/g')
EOF
    fi
  done < "$RECORDS_FILE"

  echo
  echo "Manifest preview TSV:"
  cat "$MANIFEST_PREVIEW_FILE"
  exit 0
fi

if [ -e "$OUTPUT_ROOT" ] && [ ! -d "$OUTPUT_ROOT" ]; then
  err "Output path exists but is not a directory: $OUTPUT_ROOT"
fi

if [ "$SHORTCUT_TYPE" = "alias" ]; then
  command -v osascript >/dev/null 2>&1 || err "osascript is required for alias shortcuts"
fi

mkdir -p "$OUTPUT_ROOT/_reports"
MANIFEST_FILE="$OUTPUT_ROOT/_reports/sort_manifest.tsv"
printf 'source_project\tdetected_pokemon_csv\tprimary_pokemon\tcanonical_dest\tlink_dests_csv\tstatus\n' > "$MANIFEST_FILE"

echo
echo "Applying actions:"

while IFS="$FIELD_SEP" read -r source_abs source_rel detected_csv _primary canonical_dest link_list; do
  [ -n "$source_rel" ] || continue

  canonical_abs="$OUTPUT_ROOT/$canonical_dest"
  mkdir -p "$(dirname "$canonical_abs")"
  if [ -e "$canonical_abs" ] || [ -L "$canonical_abs" ]; then
    err "Destination already exists: $canonical_abs"
  fi
  if [ "$TRANSFER_MODE" = "move" ]; then
    mv "$source_abs" "$canonical_abs"
    echo "MOVE: $source_rel -> $canonical_dest"
  else
    cp -R "$source_abs" "$canonical_abs"
    echo "COPY: $source_rel -> $canonical_dest"
  fi

  created_link=0
  if [ -n "$link_list" ]; then
    while IFS= read -r link_dest; do
      [ -n "$link_dest" ] || continue
      link_abs="$OUTPUT_ROOT/$link_dest"
      link_dir="$(dirname "$link_abs")"
      mkdir -p "$link_dir"
      if [ -e "$link_abs" ] || [ -L "$link_abs" ]; then
        err "Shortcut destination already exists: $link_abs"
      fi
      if [ "$SHORTCUT_TYPE" = "alias" ]; then
        create_finder_alias "$canonical_abs" "$link_abs"
        echo "ALIAS: $link_dest -> $canonical_dest"
      else
        rel_target="$(relative_path "$link_dir" "$canonical_abs")"
        ln -s "$rel_target" "$link_abs"
        echo "LINK: $link_dest -> $canonical_dest"
      fi
      created_link=1
    done <<EOF
$(printf '%s' "$link_list" | perl -0pe 's/\x1e/\n/g')
EOF
  fi

  status="$TRANSFER_MODE"
  if [ "$created_link" -eq 1 ]; then
    status="${TRANSFER_MODE}+${SHORTCUT_STATUS_SUFFIX}"
  fi
  link_csv_display="$(printf '%s' "$link_list" | perl -0pe 's/\x1e/,/g')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$source_rel" \
    "$detected_csv" \
    "$_primary" \
    "$canonical_dest" \
    "$link_csv_display" \
    "$status" >> "$MANIFEST_FILE"
done < "$RECORDS_FILE"

actual_canonical_dirs="$(find "$OUTPUT_ROOT" -mindepth 2 -maxdepth 2 -type d | wc -l | tr -d ' ')"
actual_shortcuts=0
missing_shortcuts=""
while IFS="$FIELD_SEP" read -r _source_abs _source_rel _detected_csv _primary _canonical_dest link_list; do
  [ -n "$link_list" ] || continue
  while IFS= read -r link_dest; do
    [ -n "$link_dest" ] || continue
    link_abs="$OUTPUT_ROOT/$link_dest"
    if [ -e "$link_abs" ] || [ -L "$link_abs" ]; then
      actual_shortcuts=$((actual_shortcuts + 1))
    else
      if [ -z "$missing_shortcuts" ]; then
        missing_shortcuts="$link_dest"
      else
        missing_shortcuts="${missing_shortcuts}"$'\n'"$link_dest"
      fi
    fi
  done <<EOF
$(printf '%s' "$link_list" | perl -0pe 's/\x1e/\n/g')
EOF
done < "$RECORDS_FILE"

if [ -n "$missing_shortcuts" ]; then
  echo "Missing shortcuts detected after apply:" >&2
  echo "$missing_shortcuts" >&2
  exit 1
fi

if [ "$SHORTCUT_TYPE" = "symlink" ]; then
  broken_links="$(find "$OUTPUT_ROOT" -type l ! -exec test -e {} \; -print)"
  if [ -n "$broken_links" ]; then
    echo "Broken symlinks detected after apply:" >&2
    echo "$broken_links" >&2
    exit 1
  fi
fi

while IFS="$FIELD_SEP" read -r source_abs _source_rel _detected_csv _primary _canonical_dest _link_list; do
  [ -n "$source_abs" ] || continue
  if [ "$TRANSFER_MODE" = "move" ]; then
    [ ! -e "$source_abs" ] || err "Source project still exists after move: $source_abs"
  else
    [ -d "$source_abs" ] || err "Source project missing after copy: $source_abs"
  fi
done < "$RECORDS_FILE"

echo
echo "Apply complete."
echo "Canonical project transfers this run: $source_count"
echo "Canonical project folders total in output: $actual_canonical_dirs"
echo "${SHORTCUT_SUMMARY_LABEL} created: $actual_shortcuts"
echo "Manifest written to: $MANIFEST_FILE"
