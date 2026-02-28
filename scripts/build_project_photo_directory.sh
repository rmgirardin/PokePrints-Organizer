#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build a photo directory by selecting a preferred image from each sorted project.

Usage:
  build_project_photo_directory.sh [--sorted-dir <path>] [--output-dir <name>] [--output-root <path>] [--dry-run|--apply] [--from-manifest|--rebuild] [--link-mode <hardlink|symlink|copy>] [--manifest-mode <append|rewrite>] [--replace] [--verbose]

Options:
  --sorted-dir <path>  Sorted root directory. Default: ./Sorted by Pokemon
  --output-dir <name>  Output folder inside sorted dir. Default: _photo_directory
  --output-root <path> Absolute/relative output path. Overrides --output-dir
  --dry-run            Plan only (default)
  --apply              Upsert assets and regenerate index from merged manifest rows
  --from-manifest      Reuse _reports/photo_manifest.tsv and skip project scanning
  --rebuild            Shortcut for --apply --from-manifest --replace
  --link-mode <mode>   How images are placed in output: hardlink, symlink, copy (default: hardlink)
  --manifest-mode <m>  append (default): keep old entries not scanned this run; rewrite: only current scan
  --replace            Replace existing output directory before rebuilding from scratch
  --verbose            Print full mapping details
  -h, --help           Show help
EOF
}

err() {
  echo "Error: $*" >&2
  exit 1
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

to_abs_path() {
  perl -MFile::Spec -e 'print File::Spec->rel2abs($ARGV[0])' "$1"
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

inode_key() {
  stat -f '%d:%i' "$1" 2>/dev/null || true
}

html_escape() {
  perl -e '
    use strict;
    use warnings;
    my $s = @ARGV ? shift : do { local $/; <STDIN> // "" };
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    print $s;
  ' "$1"
}

sanitize_manifest_field() {
  printf '%s' "${1:-}" | tr '\t\r\n' '   '
}

slugify() {
  perl -e '
    use strict;
    use warnings;
    use utf8;
    use Unicode::Normalize qw(NFKD);
    my $s = shift // "";
    $s = NFKD($s);
    $s =~ s/\pM//g;
    $s = lc $s;
    $s =~ s/[^a-z0-9]+/_/g;
    $s =~ s/_+/_/g;
    $s =~ s/^_+|_+$//g;
    $s = "project" if $s eq "";
    print $s;
  ' "$1"
}

select_preferred_image() {
  local project_abs="$1"
  local preferred_name="${2:-}"
  find "$project_abs" -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.avif' \) \
    | PREFERRED_NAME="$preferred_name" perl -ne '
        chomp;
        my $path = $_;
        my $name = lc($path);
        $name =~ s{.*/}{};
        my $stem = $name;
        $stem =~ s/\.[^.]+$//;

        my $preferred = lc($ENV{PREFERRED_NAME} // "");
        $preferred =~ s/[^a-z0-9]+//g;
        my $stem_compact = $stem;
        $stem_compact =~ s/[^a-z0-9]+//g;

        my $has_color = ($name =~ /\bcolor\b/ || $name =~ /\bcol\b/);
        my $has_one = ($name =~ /(?:^|[^0-9])1(?:[^0-9]|$)/);
        my $has_project_name = ($preferred ne "" && index($stem_compact, $preferred) >= 0);
        my $tier = 3;
        if ($has_color && $has_one) { $tier = 0; }
        elsif ($has_color) { $tier = 1; }
        elsif ($has_one) { $tier = 2; }
        my $project_name_rank = $has_project_name ? 0 : 1;
        print "$tier\t$project_name_rank\t$path\n";
      ' \
    | LC_ALL=C sort -t $'\t' -k1,1n -k2,2n -k3,3 \
    | sed -n '1s/^[0-9][0-9]*\t[0-9][0-9]*\t//p'
}

select_preferred_image_base_folder() {
  local pokemon_abs="$1"
  local preferred_name="${2:-}"
  find "$pokemon_abs" -mindepth 1 -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.avif' \) \
    | PREFERRED_NAME="$preferred_name" perl -ne '
        chomp;
        my $path = $_;
        my $name = lc($path);
        $name =~ s{.*/}{};
        my $stem = $name;
        $stem =~ s/\.[^.]+$//;

        my $preferred = lc($ENV{PREFERRED_NAME} // "");
        $preferred =~ s/[^a-z0-9]+//g;
        my $stem_compact = $stem;
        $stem_compact =~ s/[^a-z0-9]+//g;

        my $has_color = ($name =~ /\bcolor\b/ || $name =~ /\bcol\b/);
        my $has_one = ($name =~ /(?:^|[^0-9])1(?:[^0-9]|$)/);
        my $has_project_name = ($preferred ne "" && index($stem_compact, $preferred) >= 0);
        my $tier = 3;
        if ($has_color && $has_one) { $tier = 0; }
        elsif ($has_color) { $tier = 1; }
        elsif ($has_one) { $tier = 2; }
        my $project_name_rank = $has_project_name ? 0 : 1;
        print "$tier\t$project_name_rank\t$path\n";
      ' \
    | LC_ALL=C sort -t $'\t' -k1,1n -k2,2n -k3,3 \
    | sed -n '1s/^[0-9][0-9]*\t[0-9][0-9]*\t//p'
}

has_base_folder_assets() {
  local pokemon_abs="$1"
  find "$pokemon_abs" -mindepth 1 -maxdepth 1 -type f \
    \( -iname '*.stl' -o -iname '*.3mf' -o -iname '*.chitubox' \
       -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
       -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' \
       -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.avif' \) \
    | grep -q .
}

resolve_project_scan_root() {
  local project_abs="$1"
  local resolved_abs=""

  if [ -d "$project_abs" ]; then
    printf '%s' "$project_abs"
    return 0
  fi

  if [ -L "$project_abs" ]; then
    resolved_abs="$(resolve_abs_path "$project_abs")"
    if [ -n "$resolved_abs" ] && [ -d "$resolved_abs" ]; then
      printf '%s' "$resolved_abs"
      return 0
    fi
  fi

  if [ -f "$project_abs" ] && [ "${HAS_OSASCRIPT:-0}" -eq 1 ]; then
    resolved_abs="$(resolve_finder_alias_target "$project_abs" | tr -d '\r')"
    if [ -n "$resolved_abs" ] && [ -d "$resolved_abs" ]; then
      printf '%s' "$resolved_abs"
      return 0
    fi
  fi

  if [ -f "$project_abs" ]; then
    resolved_abs="$(resolve_shortcut_target_by_basename "$project_abs")"
    if [ -n "$resolved_abs" ] && [ -d "$resolved_abs" ]; then
      printf '%s' "$resolved_abs"
      return 0
    fi
  fi

  printf ''
}

project_file_summary() {
  local project_rel="$1"
  local pokemon_name="${project_rel%%/*}"
  local project_abs="$SORTED_DIR_ABS/$project_rel"
  local scan_root=""
  local scope_root=""
  local summary=""

  if [ "$project_rel" = "$pokemon_name" ]; then
    if [ ! -d "$project_abs" ]; then
      printf '0 total'
      return 0
    fi
    summary="$(
      find "$project_abs" -mindepth 1 -maxdepth 1 -type f \
        | perl -e '
            use strict;
            use warnings;
            sub file_type_label {
              my ($ext) = @_;
              my %labels = (
                stl => "STL",
                "3mf" => "3MF",
                obj => "OBJ",
                step => "STEP",
                stp => "STEP",
                chitubox => "CHITUBOX",
                png => "PNG",
                jpg => "JPEG",
                jpeg => "JPEG",
                webp => "WebP",
                gif => "GIF",
                bmp => "BMP",
                tif => "TIFF",
                tiff => "TIFF",
                heic => "HEIC",
                heif => "HEIF",
                avif => "AVIF",
                svg => "SVG",
                pdf => "PDF",
                txt => "Text",
                md => "Markdown",
                json => "JSON",
                csv => "CSV",
                zip => "ZIP",
              );

              return "No ext" if $ext eq "no extension";
              return $labels{$ext} if exists $labels{$ext};
              return uc($ext);
            }

            my %counts;
            my $total = 0;
            while (my $path = <STDIN>) {
              chomp $path;
              next if $path eq "";
              $total++;
              my $name = $path;
              $name =~ s{.*/}{};
              my $ext = "no extension";
              if ($name =~ /\.([^.]+)$/) {
                $ext = lc $1;
              }
              $counts{$ext}++;
            }

            print "$total total";
            if ($total > 0) {
              my @parts = map {
                my $label = file_type_label($_);
                "$label: $counts{$_}"
              } sort { $counts{$b} <=> $counts{$a} || $a cmp $b } keys %counts;
              print " (" . join(", ", @parts) . ")";
            }
          '
    )"
    printf '%s' "${summary:-0 total}"
    return 0
  fi

  scan_root="$(resolve_project_scan_root "$project_abs")"
  if [ -z "$scan_root" ] || [ ! -d "$scan_root" ]; then
    printf '0 total'
    return 0
  fi
  scope_root="$scan_root"

  summary="$(
    find "$scope_root" -type f \
      | perl -e '
          use strict;
          use warnings;
          sub file_type_label {
            my ($ext) = @_;
            my %labels = (
              stl => "STL",
              "3mf" => "3MF",
              obj => "OBJ",
              step => "STEP",
              stp => "STEP",
              chitubox => "CHITUBOX",
              png => "PNG",
              jpg => "JPEG",
              jpeg => "JPEG",
              webp => "WebP",
              gif => "GIF",
              bmp => "BMP",
              tif => "TIFF",
              tiff => "TIFF",
              heic => "HEIC",
              heif => "HEIF",
              avif => "AVIF",
              svg => "SVG",
              pdf => "PDF",
              txt => "Text",
              md => "Markdown",
              json => "JSON",
              csv => "CSV",
              zip => "ZIP",
            );

            return "No ext" if $ext eq "no extension";
            return $labels{$ext} if exists $labels{$ext};
            return uc($ext);
          }

          my %counts;
          my $total = 0;
          while (my $path = <STDIN>) {
            chomp $path;
            next if $path eq "";
            $total++;
            my $name = $path;
            $name =~ s{.*/}{};
            my $ext = "no extension";
            if ($name =~ /\.([^.]+)$/) {
              $ext = lc $1;
            }
            $counts{$ext}++;
          }

          print "$total total";
          if ($total > 0) {
            my @parts = map {
              my $label = file_type_label($_);
              "$label: $counts{$_}"
            } sort { $counts{$b} <=> $counts{$a} || $a cmp $b } keys %counts;
            print " (" . join(", ", @parts) . ")";
          }
        '
  )"

  printf '%s' "${summary:-0 total}"
}

resolve_shortcut_target_by_basename() {
  local shortcut_abs="$1"
  local base_name
  local candidate

  [ -n "${CANONICAL_PROJECT_DIRS_FILE:-}" ] || return 0
  [ -f "$CANONICAL_PROJECT_DIRS_FILE" ] || return 0

  base_name="$(basename "$shortcut_abs")"
  candidate="$(awk -v b="$base_name" '
    {
      name = $0
      sub(/^.*\//, "", name)
      if (name == b) {
        count++
        if (count == 1) {
          first = $0
        }
      }
    }
    END {
      if (count == 1) {
        print first
      }
    }
  ' "$CANONICAL_PROJECT_DIRS_FILE")"

  printf '%s' "$candidate"
}

normalized_name_key() {
  local raw="${1:-}"
  printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

is_ignorable_support_project() {
  local key
  key="$(normalized_name_key "$1")"
  case "$key" in
    fdm|hinge|hingeparts|multimaterial|presup|presupport|presupported|resin|singlematerial|supported)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

MODE="dry-run"
VERBOSE=0
REPLACE=0
SORTED_DIR="./Sorted by Pokemon"
OUTPUT_DIR_NAME="_photo_directory"
OUTPUT_ROOT_OVERRIDE=""
LINK_MODE="hardlink"
MANIFEST_MODE="append"
PLAN_SOURCE="scan"
HAS_OSASCRIPT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sorted-dir)
      shift
      [ "$#" -gt 0 ] || err "--sorted-dir requires a value"
      SORTED_DIR="$1"
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
    --from-manifest)
      PLAN_SOURCE="manifest"
      ;;
    --rebuild)
      MODE="apply"
      PLAN_SOURCE="manifest"
      REPLACE=1
      ;;
	  --link-mode)
		shift
		[ "$#" -gt 0 ] || err "--link-mode requires a value"
		case "$1" in
		  hardlink|symlink|copy)
			LINK_MODE="$1"
			;;
		  *)
			err "--link-mode must be one of: hardlink, symlink, copy"
			;;
		esac
      ;;
    --manifest-mode)
      shift
      [ "$#" -gt 0 ] || err "--manifest-mode requires a value"
      case "$1" in
        append|rewrite)
          MANIFEST_MODE="$1"
          ;;
        *)
          err "--manifest-mode must be one of: append, rewrite"
          ;;
      esac
      ;;
    --replace)
      REPLACE=1
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
if [ -n "$OUTPUT_ROOT_OVERRIDE" ]; then
  OUTPUT_DIR_ABS="$(to_abs_path "$OUTPUT_ROOT_OVERRIDE")"
else
  OUTPUT_DIR_ABS="$SORTED_DIR_ABS/$OUTPUT_DIR_NAME"
fi
if [ "$OUTPUT_DIR_ABS" = "$SORTED_DIR_ABS" ]; then
  err "Output path cannot be the same as sorted directory: $OUTPUT_DIR_ABS"
fi
OUTPUT_ROOT_WITHIN_SORTED=0
case "$OUTPUT_DIR_ABS" in
  "$SORTED_DIR_ABS"/*)
    OUTPUT_ROOT_WITHIN_SORTED=1
    ;;
esac
IMAGES_DIR_ABS="$OUTPUT_DIR_ABS/images"
REPORTS_DIR_ABS="$OUTPUT_DIR_ABS/_reports"
MANIFEST_FILE="$REPORTS_DIR_ABS/photo_manifest.tsv"
HTML_INDEX_FILE="$OUTPUT_DIR_ABS/Directory.html"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/build-photo-directory.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

FS=$'\x1f'
PROJECTS_FILE="$TMP_DIR/projects.txt"
PLAN_FILE="$TMP_DIR/plan.tsv"
ALIAS_CANDIDATES_FILE="$TMP_DIR/alias_candidates.txt"
CANONICAL_PROJECT_DIRS_FILE="$TMP_DIR/canonical_projects.txt"
CANONICAL_PROJECTS_RAW_FILE="$TMP_DIR/canonical_projects_raw.txt"
MANIFEST_PLAN_SOURCE_FILE="$TMP_DIR/manifest_plan_source.tsv"

if [ "$PLAN_SOURCE" = "manifest" ]; then
  [ -f "$MANIFEST_FILE" ] || err "--from-manifest requires an existing manifest: $MANIFEST_FILE"
  cp "$MANIFEST_FILE" "$MANIFEST_PLAN_SOURCE_FILE"
fi

if command -v osascript >/dev/null 2>&1; then
  HAS_OSASCRIPT=1
fi

is_within_output_root() {
  local path_abs="$1"
  [ "$OUTPUT_ROOT_WITHIN_SORTED" -eq 1 ] || return 1
  case "$path_abs" in
    "$OUTPUT_DIR_ABS"|"${OUTPUT_DIR_ABS}"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

: > "$PLAN_FILE"

project_total=0
selected_total=0
missing_total=0
ignored_total=0
if [ "$PLAN_SOURCE" = "scan" ]; then
  find "$SORTED_DIR_ABS" -mindepth 2 -maxdepth 2 -type d | LC_ALL=C sort > "$CANONICAL_PROJECTS_RAW_FILE"
  : > "$CANONICAL_PROJECT_DIRS_FILE"
  while IFS= read -r canonical_abs; do
    [ -n "$canonical_abs" ] || continue
    is_within_output_root "$canonical_abs" && continue
    printf '%s\n' "$canonical_abs" >> "$CANONICAL_PROJECT_DIRS_FILE"
  done < "$CANONICAL_PROJECTS_RAW_FILE"
  cp "$CANONICAL_PROJECT_DIRS_FILE" "$PROJECTS_FILE"
  find "$SORTED_DIR_ABS" -mindepth 2 -maxdepth 2 -type l | LC_ALL=C sort >> "$PROJECTS_FILE"

  find "$SORTED_DIR_ABS" -mindepth 2 -maxdepth 2 -type f | LC_ALL=C sort > "$ALIAS_CANDIDATES_FILE"
  while IFS= read -r alias_abs; do
    [ -n "$alias_abs" ] || continue
    is_within_output_root "$alias_abs" && continue
    alias_rel="${alias_abs#$SORTED_DIR_ABS/}"
    alias_pokemon="${alias_rel%%/*}"
    [ "$alias_pokemon" != "_reports" ] || continue

    alias_target=""
    if [ "$HAS_OSASCRIPT" -eq 1 ]; then
      alias_target="$(resolve_finder_alias_target "$alias_abs" | tr -d '\r')"
    fi
    if [ -z "$alias_target" ]; then
      alias_target="$(resolve_shortcut_target_by_basename "$alias_abs")"
    fi

    [ -n "$alias_target" ] || continue
    [ -d "$alias_target" ] || continue
    case "$alias_target" in
      "$SORTED_DIR_ABS"/*)
        printf '%s\n' "$alias_abs" >> "$PROJECTS_FILE"
        ;;
      *)
        continue
        ;;
    esac
  done < "$ALIAS_CANDIDATES_FILE"

  while IFS= read -r pokemon_abs; do
    [ -n "$pokemon_abs" ] || continue
    is_within_output_root "$pokemon_abs" && continue
    pokemon_name="$(basename "$pokemon_abs")"
    [ "$pokemon_name" != "_reports" ] || continue
    # Include base Pokemon folder only if it contains direct files.
    if has_base_folder_assets "$pokemon_abs"; then
      printf '%s\n' "$pokemon_abs" >> "$PROJECTS_FILE"
    fi
  done < <(find "$SORTED_DIR_ABS" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)

  LC_ALL=C sort -u "$PROJECTS_FILE" -o "$PROJECTS_FILE"

  while IFS= read -r project_abs; do
    [ -n "$project_abs" ] || continue
    is_within_output_root "$project_abs" && continue
    project_rel="${project_abs#$SORTED_DIR_ABS/}"
    pokemon="${project_rel%%/*}"
    [ "$pokemon" != "_reports" ] || continue
    [ "$pokemon" != "$OUTPUT_DIR_NAME" ] || continue

    if [ "$project_rel" != "$pokemon" ]; then
      project_name="${project_rel#*/}"
      if is_ignorable_support_project "$project_name"; then
        ignored_total=$((ignored_total + 1))
        continue
      fi
    fi

    project_total=$((project_total + 1))
    project_file_summary_text="$(project_file_summary "$project_rel")"
    project_file_summary_text="$(sanitize_manifest_field "$project_file_summary_text")"
    project_file_total="${project_file_summary_text%% total*}"
    if ! [[ "$project_file_total" =~ ^[0-9]+$ ]]; then
      project_file_total="0"
    fi

    if [ "$project_rel" = "$pokemon" ]; then
      # Base Pokemon folder candidate; only check direct files to avoid
      # accidentally selecting images from nested project folders.
      first_image="$(select_preferred_image_base_folder "$project_abs" "$pokemon")"
    else
      scan_root_abs="$(resolve_project_scan_root "$project_abs")"
      if [ -n "$scan_root_abs" ]; then
        first_image="$(select_preferred_image "$scan_root_abs" "$project_name")"
      else
        first_image=""
      fi
    fi

    if [ -z "$first_image" ]; then
      printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
        "$project_rel" "$FS" "-" "$FS" "-" "$FS" "-" "$FS" "no_image" "$FS" "$project_file_total" "$FS" "$project_file_summary_text" >> "$PLAN_FILE"
      missing_total=$((missing_total + 1))
      continue
    fi

    source_rel="${first_image#$SORTED_DIR_ABS/}"
    base_name="$(basename "$first_image")"
    pokemon_name="${project_rel%%/*}"
    ext=""
    if [[ "$base_name" == *.* && "$base_name" != .* ]]; then
      ext="${base_name##*.}"
      ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    fi
    [ -n "$ext" ] || ext="img"

    pokemon_slug="$(slugify "$pokemon_name")"
    project_slug="$(slugify "$project_rel")"
    output_name="${project_slug}.${ext}"
    output_rel="images/$pokemon_slug/$output_name"

    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
      "$project_rel" "$FS" "$source_rel" "$FS" "$output_rel" "$FS" "$first_image" "$FS" "selected" "$FS" "$project_file_total" "$FS" "$project_file_summary_text" >> "$PLAN_FILE"

    selected_total=$((selected_total + 1))
  done < "$PROJECTS_FILE"
else
  awk -F $'\t' -v OFS="$FS" -v sorted_root="$SORTED_DIR_ABS/" '
    NR == 1 { next }
    $1 == "" { next }
    {
      project_path = $1
      source_image_path = $2
      photo_asset_path = $3
      row_status = $4
      project_file_total = $5
      project_file_summary = $6

      source_abs = "-"
      plan_status = row_status

      if (source_image_path != "" && photo_asset_path != "") {
        source_abs = sorted_root source_image_path
        plan_status = "selected"
      } else if (plan_status == "") {
        plan_status = "no_image"
      }

      print project_path, source_image_path, photo_asset_path, source_abs, plan_status, project_file_total, project_file_summary
    }
  ' "$MANIFEST_PLAN_SOURCE_FILE" > "$PLAN_FILE"

  project_total="$(awk 'END { print NR + 0 }' "$PLAN_FILE")"
  selected_total="$(awk -F "$FS" '$5 == "selected" { count++ } END { print count + 0 }' "$PLAN_FILE")"
  missing_total=$((project_total - selected_total))
fi

echo "Sorted directory: $SORTED_DIR_ABS"
echo "Mode: $MODE"
echo "Plan source: $PLAN_SOURCE"
echo "Output directory: $OUTPUT_DIR_ABS"
echo "Link mode: $LINK_MODE"
echo "Manifest mode: $MANIFEST_MODE"
if [ "$PLAN_SOURCE" = "scan" ]; then
  echo "Projects scanned: $project_total"
else
  echo "Projects loaded from manifest: $project_total"
fi
echo "Projects with selected image: $selected_total"
echo "Projects without image: $missing_total"
echo "Projects ignored (support folders): $ignored_total"

if [ "$VERBOSE" -eq 1 ] || [ "$MODE" = "dry-run" ]; then
  echo
  echo "Plan:"
  while IFS="$FS" read -r project_rel source_rel output_rel _source_abs status project_file_total project_file_summary_text; do
    [ -n "$project_rel" ] || continue
    if [ "$status" = "selected" ]; then
      echo "SELECT: $project_rel -> $source_rel => $output_rel | Files: $project_file_summary_text"
    else
      echo "NO IMAGE: $project_rel | Files: $project_file_summary_text"
    fi
  done < <(LC_ALL=C sort -t "$FS" -k1,1 "$PLAN_FILE")
fi

if [ "$MODE" = "dry-run" ]; then
  exit 0
fi

if [ -e "$OUTPUT_DIR_ABS" ] && [ ! -d "$OUTPUT_DIR_ABS" ]; then
  err "Output path exists but is not a directory: $OUTPUT_DIR_ABS"
fi

if [ -d "$OUTPUT_DIR_ABS" ]; then
  existing_entries="$(find "$OUTPUT_DIR_ABS" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  if [ "$existing_entries" -gt 0 ]; then
    if [ "$REPLACE" -eq 1 ]; then
      rm -rf "$OUTPUT_DIR_ABS"
    fi
  fi
fi

mkdir -p "$IMAGES_DIR_ABS" "$REPORTS_DIR_ABS"
if [ -d "$OUTPUT_DIR_ABS/images" ]; then
  find "$OUTPUT_DIR_ABS/images" -mindepth 1 -type d -empty -delete 2>/dev/null || true
fi

CURRENT_MANIFEST_ROWS_FILE="$TMP_DIR/current_manifest_rows.tsv"
EXISTING_MANIFEST_ROWS_FILE="$TMP_DIR/existing_manifest_rows.tsv"
MERGED_MANIFEST_ROWS_FILE="$TMP_DIR/merged_manifest_rows.tsv"
: > "$CURRENT_MANIFEST_ROWS_FILE"
: > "$EXISTING_MANIFEST_ROWS_FILE"
: > "$MERGED_MANIFEST_ROWS_FILE"

if [ "$REPLACE" -eq 0 ] && [ -f "$MANIFEST_FILE" ]; then
  awk -F $'\t' -v OFS=$'\t' '
    NR == 1 { next }
    $1 == "" { next }
    {
      project_path = $1
      source_image_path = $2
      photo_asset_path = $3
      status = $4
      project_file_total = $5
      project_file_summary = $6
      print project_path, source_image_path, photo_asset_path, status, project_file_total, project_file_summary
    }
  ' "$MANIFEST_FILE" > "$EXISTING_MANIFEST_ROWS_FILE"
fi

while IFS="$FS" read -r project_rel source_rel output_rel source_abs status project_file_total project_file_summary_text; do
  [ -n "$project_rel" ] || continue
  if [ "$status" != "selected" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$project_rel" "" "" "$status" "$project_file_total" "$project_file_summary_text" >> "$CURRENT_MANIFEST_ROWS_FILE"
    continue
  fi

  if [ ! -f "$source_abs" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$project_rel" "$source_rel" "$output_rel" "source_missing" "$project_file_total" "$project_file_summary_text" >> "$CURRENT_MANIFEST_ROWS_FILE"
    continue
  fi

  dest_abs="$OUTPUT_DIR_ABS/$output_rel"
  dest_dir="$(dirname "$dest_abs")"
  mkdir -p "$dest_dir"

  prefix="${dest_abs%.*}"
  for old_candidate in "${prefix}".*; do
    [ -e "$old_candidate" ] || [ -L "$old_candidate" ] || continue
    [ "$old_candidate" = "$dest_abs" ] && continue
    rm -f "$old_candidate"
  done

  skip_update=0
  placed_status="$LINK_MODE"
	if [ -e "$dest_abs" ] || [ -L "$dest_abs" ]; then
	  case "$LINK_MODE" in
		hardlink)
		  if [ "$(inode_key "$dest_abs")" = "$(inode_key "$source_abs")" ]; then
			skip_update=1
			placed_status="unchanged"
		  fi
		  ;;
		symlink)
		  rel_target="$(relative_path "$dest_dir" "$source_abs")"
		  if [ -L "$dest_abs" ] && [ "$(readlink "$dest_abs")" = "$rel_target" ]; then
			skip_update=1
			placed_status="unchanged"
		  fi
		  ;;
		copy)
		  if [ -f "$dest_abs" ] && cmp -s "$dest_abs" "$source_abs"; then
			skip_update=1
			placed_status="unchanged"
		  fi
		  ;;
	  esac
  fi

  if [ "$skip_update" -eq 0 ] && ([ -e "$dest_abs" ] || [ -L "$dest_abs" ]); then
	  rm -f "$dest_abs"
  fi

  if [ "$skip_update" -eq 1 ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$project_rel" "$source_rel" "$output_rel" "$placed_status" "$project_file_total" "$project_file_summary_text" >> "$CURRENT_MANIFEST_ROWS_FILE"
    continue
  fi

  case "$LINK_MODE" in
	  hardlink)
		if ln "$source_abs" "$dest_abs" 2>/dev/null; then
		  :
		else
		  cp -p "$source_abs" "$dest_abs"
		  placed_status="copy_fallback"
		fi
		;;
	  symlink)
		rel_target="$(relative_path "$dest_dir" "$source_abs")"
		ln -s "$rel_target" "$dest_abs"
		;;
	  copy)
		cp -p "$source_abs" "$dest_abs"
		;;
	esac

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$project_rel" "$source_rel" "$output_rel" "$placed_status" "$project_file_total" "$project_file_summary_text" >> "$CURRENT_MANIFEST_ROWS_FILE"
done < "$PLAN_FILE"

if [ "$MANIFEST_MODE" = "append" ] && [ "$REPLACE" -eq 0 ] && [ -s "$EXISTING_MANIFEST_ROWS_FILE" ]; then
  awk -F $'\t' '
    FILENAME == ARGV[1] { seen[$1] = 1; next }
    !seen[$1] { print $0 }
  ' "$CURRENT_MANIFEST_ROWS_FILE" "$EXISTING_MANIFEST_ROWS_FILE" > "$MERGED_MANIFEST_ROWS_FILE"
  cat "$CURRENT_MANIFEST_ROWS_FILE" >> "$MERGED_MANIFEST_ROWS_FILE"
else
  cp "$CURRENT_MANIFEST_ROWS_FILE" "$MERGED_MANIFEST_ROWS_FILE"
fi

printf 'project_path\tsource_image_path\tphoto_asset_path\tstatus\tproject_file_total\tproject_file_summary\n' > "$MANIFEST_FILE"
if [ -s "$MERGED_MANIFEST_ROWS_FILE" ]; then
  LC_ALL=C sort -t $'\t' -k1,1 "$MERGED_MANIFEST_ROWS_FILE" >> "$MANIFEST_FILE"
fi

{
  cat <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>MyPokePrints Photo Directory</title>
  <style>
    :root {
      --bg: #f5f2ea;
      --card: #fffdfa;
      --ink: #1f1d1a;
      --muted: #6b6258;
      --line: #ded7ca;
      --accent: #9a3d12;
    }
    body {
      margin: 0;
      font-family: "Avenir Next", "Segoe UI", sans-serif;
      background: radial-gradient(circle at top right, #efe4cf 0%, var(--bg) 50%, #efe8dc 100%);
      color: var(--ink);
    }
    main {
      max-width: 1200px;
      margin: 0 auto;
      padding: 2rem 1.2rem 3rem;
    }
    h1 {
      margin: 0 0 0.4rem;
      font-size: clamp(1.4rem, 3vw, 2rem);
    }
    h2 {
      margin: 1.4rem 0 0.6rem;
      font-size: clamp(1rem, 2vw, 1.2rem);
      border-bottom: 1px solid var(--line);
      padding-bottom: 0.25rem;
    }
    p.meta {
      margin: 0 0 1.2rem;
      color: var(--muted);
    }
    .search-wrap {
      display: grid;
      gap: 0.35rem;
      margin: 0 0 1.2rem;
    }
    .search-input {
      width: min(560px, 100%);
      font: inherit;
      color: var(--ink);
      background: #fffdf9;
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 0.55rem 0.75rem;
    }
    .search-input:focus-visible {
      outline: 2px solid var(--accent);
      outline-offset: 1px;
    }
    .search-meta {
      margin: 0;
      font-size: 0.85rem;
    }
    .is-hidden {
      display: none !important;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(360px, 1fr));
      gap: 0.9rem;
    }
    .row {
      display: grid;
      grid-template-columns: 140px 1fr;
      gap: 0.8rem;
      align-items: start;
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 0.75rem;
      box-shadow: 0 4px 18px rgba(40, 26, 5, 0.08);
    }
    .thumb {
      width: 140px;
      height: 140px;
      object-fit: cover;
      border-radius: 8px;
      border: 1px solid var(--line);
      background: #e9e1d4;
    }
    .thumb-button {
      width: 140px;
      height: 140px;
      padding: 0;
      border: 0;
      background: transparent;
      cursor: zoom-in;
      display: block;
    }
    .thumb-button:focus-visible {
      outline: 2px solid var(--accent);
      outline-offset: 2px;
      border-radius: 10px;
    }
    .details {
      font-size: 0.9rem;
      line-height: 1.3;
    }
    .path {
      word-break: break-word;
      margin: 0.2rem 0;
    }
    .empty {
      background: #fff3e8;
    }
    code {
      font-family: "SF Mono", Menlo, Monaco, monospace;
      font-size: 0.8rem;
      color: #2c2520;
    }
    body.lightbox-open {
      overflow: hidden;
    }
    .lightbox {
      position: fixed;
      inset: 0;
      z-index: 9999;
      background: rgba(16, 12, 8, 0.82);
      display: none;
      align-items: center;
      justify-content: center;
      flex-direction: column;
      padding: 1rem;
    }
    .lightbox.is-open {
      display: flex;
    }
    .lightbox-image {
      max-width: min(96vw, 1400px);
      max-height: 84vh;
      object-fit: contain;
      border-radius: 12px;
      box-shadow: 0 14px 40px rgba(0, 0, 0, 0.5);
      background: #0b0b0b;
    }
    .lightbox-close {
      position: absolute;
      top: 0.8rem;
      right: 0.8rem;
      border: 1px solid #e6dcc8;
      background: #f7f1e6;
      color: #1f1d1a;
      border-radius: 999px;
      width: 2.2rem;
      height: 2.2rem;
      line-height: 2rem;
      font-size: 1.3rem;
      cursor: pointer;
    }
    .lightbox-caption {
      margin: 0.7rem 0 0;
      color: #f2ede3;
      font-size: 0.9rem;
      text-align: center;
      max-width: min(96vw, 1400px);
      word-break: break-word;
    }
  </style>
</head>
<body>
  <main>
HTML_HEAD

  selected_count="$(awk -F $'\t' 'NR>1 && $4 != "no_image" {count++} END {print count+0}' "$MANIFEST_FILE")"
  missing_count="$(awk -F $'\t' 'NR>1 && $4 == "no_image" {count++} END {print count+0}' "$MANIFEST_FILE")"
  indexed_file_count="$(awk -F $'\t' 'NR>1 && $5 ~ /^[0-9]+$/ {sum+=$5} END {print sum+0}' "$MANIFEST_FILE")"
  printf '    <h1>MyPokePrints Photo Directory</h1>\n'
  printf '    <p class="meta">Selected images: %s | Projects without image: %s | Indexed files: %s</p>\n' "$selected_count" "$missing_count" "$indexed_file_count"
  printf '    <section class="search-wrap">\n'
  printf '      <input id="directory-search" class="search-input" type="search" placeholder="Search Pokemon or project" aria-label="Search Pokemon or project" autocomplete="off" />\n'
  printf '      <p id="search-summary" class="meta search-meta" aria-live="polite"></p>\n'
  printf '    </section>\n'
  if [ "$selected_count" -eq 0 ]; then
    printf '    <p class="meta">No preview images were indexed. Verify <code>--sorted-dir</code> and rerun with <code>--apply</code>.</p>\n'
  fi

  current_pokemon=""
  while IFS="$FS" read -r project_path source_image_path photo_asset_path row_status project_file_total project_file_summary_text; do
    [ -n "$project_path" ] || continue

    pokemon_name="${project_path%%/*}"
    if [ "$pokemon_name" != "$current_pokemon" ]; then
      if [ -n "$current_pokemon" ]; then
        printf '    </div>\n'
      fi
      pokemon_header_html="$(html_escape "$pokemon_name")"
      printf '    <h2>%s</h2>\n' "$pokemon_header_html"
      printf '    <div class="grid">\n'
      current_pokemon="$pokemon_name"
    fi

    pokemon_html="$(html_escape "$pokemon_name")"
    project_name="${project_path#*/}"
    if [ "$project_name" = "$project_path" ]; then
      project_name="$project_path"
    fi
    project_html="$(html_escape "$project_name")"
    if [ -z "$project_file_summary_text" ] && [ -n "$project_file_total" ]; then
      project_file_summary_text="${project_file_total} total"
    fi
    if [ -z "$project_file_summary_text" ]; then
      project_file_summary_text="Not captured (rerun with --apply to refresh)"
    fi
    project_file_summary_html="$(html_escape "$project_file_summary_text")"
    search_text="$pokemon_name $project_name $project_path $project_file_summary_text"
    search_html="$(html_escape "$search_text")"
    if [ "$row_status" = "no_image" ]; then
      printf '      <article class="row empty" data-search="%s">\n' "$search_html"
      printf '        <div class="thumb"></div>\n'
      printf '        <div class="details">\n'
      printf '          <div class="path"><strong>Pokemon:</strong> <code>%s</code></div>\n' "$pokemon_html"
      printf '          <div class="path"><strong>Project:</strong> <code>%s</code></div>\n' "$project_html"
      printf '          <div class="path"><strong>Files:</strong> <code>%s</code></div>\n' "$project_file_summary_html"
      printf '        </div>\n'
      printf '      </article>\n'
      continue
    fi

    photo_html="$(html_escape "$photo_asset_path")"
    printf '      <article class="row" data-search="%s">\n' "$search_html"
    printf '        <button class="thumb-button" type="button" data-full="%s" data-alt="%s" aria-label="Open image preview">\n' "$photo_html" "$project_html"
    printf '          <img class="thumb" loading="lazy" src="%s" alt="%s" />\n' "$photo_html" "$project_html"
    printf '        </button>\n'
    printf '        <div class="details">\n'
    printf '          <div class="path"><strong>Pokemon:</strong> <code>%s</code></div>\n' "$pokemon_html"
    printf '          <div class="path"><strong>Project:</strong> <code>%s</code></div>\n' "$project_html"
    printf '          <div class="path"><strong>Files:</strong> <code>%s</code></div>\n' "$project_file_summary_html"
    printf '        </div>\n'
    printf '      </article>\n'
  done < <(awk -F $'\t' -v OFS="$FS" 'NR > 1 {print $1, $2, $3, $4, $5, $6}' "$MANIFEST_FILE" | LC_ALL=C sort -t "$FS" -k1,1)

  if [ -n "$current_pokemon" ]; then
    printf '    </div>\n'
  fi

  if [ "$selected_count" -gt 0 ]; then
  cat <<'HTML_LIGHTBOX'
  </main>
  <div id="lightbox" class="lightbox" aria-hidden="true">
    <button id="lightbox-close" class="lightbox-close" type="button" aria-label="Close image preview">&times;</button>
    <img id="lightbox-image" class="lightbox-image" alt="" />
    <p id="lightbox-caption" class="lightbox-caption"></p>
  </div>
HTML_LIGHTBOX
  else
    printf '  </main>\n'
  fi

  cat <<'HTML_FOOT'
  <script>
    (() => {
      const searchInput = document.getElementById("directory-search");
      const searchSummary = document.getElementById("search-summary");
      const rows = Array.from(document.querySelectorAll(".row"));
      const pokemonHeaders = Array.from(document.querySelectorAll("main h2"));

      const applyFilter = () => {
        const query = searchInput ? searchInput.value.trim().toLocaleLowerCase() : "";
        let visibleRows = 0;

        rows.forEach((row) => {
          const haystack = (row.dataset.search || "").toLocaleLowerCase();
          const matches = query === "" || haystack.includes(query);
          row.classList.toggle("is-hidden", !matches);
          if (matches) {
            visibleRows += 1;
          }
        });

        pokemonHeaders.forEach((header) => {
          const grid = header.nextElementSibling;
          if (!grid || !grid.classList.contains("grid")) {
            return;
          }
          const hasVisibleRows = grid.querySelector(".row:not(.is-hidden)") !== null;
          header.classList.toggle("is-hidden", !hasVisibleRows);
          grid.classList.toggle("is-hidden", !hasVisibleRows);
        });

        if (searchSummary) {
          searchSummary.textContent = query === ""
            ? `Showing all ${visibleRows} projects`
            : `Showing ${visibleRows} matching projects`;
        }
      };

      if (searchInput) {
        searchInput.addEventListener("input", applyFilter);
      }
      applyFilter();

      const lightbox = document.getElementById("lightbox");
      const lightboxImage = document.getElementById("lightbox-image");
      const lightboxCaption = document.getElementById("lightbox-caption");
      const closeButton = document.getElementById("lightbox-close");
      const openers = Array.from(document.querySelectorAll(".thumb-button"));
      if (!lightbox || !lightboxImage || !lightboxCaption || !closeButton || openers.length === 0) return;

      const openLightbox = (src, alt) => {
        if (!src) return;
        lightboxImage.src = src;
        lightboxImage.alt = alt || "";
        lightboxCaption.textContent = alt || "";
        lightbox.classList.add("is-open");
        lightbox.setAttribute("aria-hidden", "false");
        document.body.classList.add("lightbox-open");
      };

      const closeLightbox = () => {
        lightbox.classList.remove("is-open");
        lightbox.setAttribute("aria-hidden", "true");
        lightboxImage.removeAttribute("src");
        lightboxImage.alt = "";
        lightboxCaption.textContent = "";
        document.body.classList.remove("lightbox-open");
      };

      openers.forEach((button) => {
        button.addEventListener("click", () => {
          openLightbox(button.dataset.full || "", button.dataset.alt || "");
        });
      });

      closeButton.addEventListener("click", closeLightbox);
      lightbox.addEventListener("click", (event) => {
        if (event.target === lightbox) {
          closeLightbox();
        }
      });

      document.addEventListener("keydown", (event) => {
        if (event.key === "Escape" && lightbox.classList.contains("is-open")) {
          closeLightbox();
        }
      });
    })();
  </script>
</body>
</html>
HTML_FOOT
} > "$HTML_INDEX_FILE"

echo
echo "Apply complete."
echo "Manifest: $MANIFEST_FILE"
echo "Gallery: $HTML_INDEX_FILE"
