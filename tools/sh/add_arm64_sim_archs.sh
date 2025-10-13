#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/xlib.sh"

BASE_DIR=$1
PLIST_BUDDY='/usr/libexec/PlistBuddy'
FAT_ARM64_X86_64_SIMULATOR_ID='ios-arm64_x86_64-simulator'

main() {
  fixed_static_deps=()
  fixed_dynamic_deps=()
  unfixable_deps=()

  for XCFRAMEWORK in "$BASE_DIR"/*.xcframework; do
    handle_xcfamework
  done

  if [ ${#fixed_dynamic_deps[@]} -gt 0 ]; then
    log_success "Fixed ${#fixed_dynamic_deps[@]} dynamic Rosetta deps:" \
      "${fixed_dynamic_deps[@]}"
  fi
  if [ ${#fixed_static_deps[@]} -gt 0 ]; then
    log_success "Fixed ${#fixed_static_deps[@]} static Rosetta deps:" \
      "${fixed_static_deps[@]}"
  fi
  if [ ${#unfixable_deps[@]} -gt 0 ]; then
    log_error "Unable to fix ${#unfixable_deps[@]} deps!" \
      "${unfixable_deps[@]}"
    return 27
  fi
}

handle_xcfamework() {
  log_info "Checking $XCFRAMEWORK"
  local info_plist="$XCFRAMEWORK/Info.plist"

  if [ ! -f "$info_plist" ]; then
    log_warn "Info.plist not found in $XCFRAMEWORK"
    return
  fi

  NAME=$(basename "$XCFRAMEWORK" .xcframework)
  X86_64_SIMULATOR_PATH=''
  ARM64_DEVICE_PATH=''
  ARM64_SIMULATOR_DIR="$XCFRAMEWORK/ios-arm64-simulator"
  ARM64_SIMULATOR_PATH="$ARM64_SIMULATOR_DIR/$NAME"
  FAT_ARM64_X86_64_SIMULATOR_DIR="$XCFRAMEWORK/$FAT_ARM64_X86_64_SIMULATOR_ID"
  FAT_ARM64_X86_64_SIMULATOR_PATH="$FAT_ARM64_X86_64_SIMULATOR_DIR/$NAME"

  local lib_count=$($PLIST_BUDDY -c "Print :AvailableLibraries" "$info_plist" 2>/dev/null | grep -c "Dict")

  local found_rosetta_only_sym=false
  local found_device_arm64=false
  local is_dynamic=false
  local rosetta_only_sim_index=0

  for ((i=0; i<lib_count; i++)); do
    local platform=$($PLIST_BUDDY -c "Print :AvailableLibraries:$i:SupportedPlatform" "$info_plist" 2>/dev/null)

    if [ "$platform" != 'ios' ]; then continue; fi

    local platform_variant=$($PLIST_BUDDY -c "Print :AvailableLibraries:$i:SupportedPlatformVariant" "$info_plist" 2>/dev/null)
    local supported_archs=$($PLIST_BUDDY -c "Print :AvailableLibraries:$i:SupportedArchitectures" "$info_plist" 2>/dev/null)

    if [ "$platform_variant" = 'simulator' ]; then
      if [[ "$supported_archs" == *x86_64* ]] && [[ "$supported_archs" != *arm64* ]]; then
        found_rosetta_only_sym=true
        rosetta_only_sim_index=$i
        local library_id=$($PLIST_BUDDY -c "Print :AvailableLibraries:$i:LibraryIdentifier" "$info_plist" 2>/dev/null)
        local library_path=$($PLIST_BUDDY -c "Print :AvailableLibraries:$i:LibraryPath" "$info_plist" 2>/dev/null)
        X86_64_SIMULATOR_DIR="$XCFRAMEWORK/$library_id"
        X86_64_SIMULATOR_PATH="$X86_64_SIMULATOR_DIR/$library_path/$NAME"
      fi
    elif [[ "$supported_archs" == *arm64* ]]; then
      found_device_arm64=true
      local library_id=$($PLIST_BUDDY -c "Print :AvailableLibraries:$i:LibraryIdentifier" "$info_plist" 2>/dev/null)
      local library_path=$($PLIST_BUDDY -c "Print :AvailableLibraries:$i:LibraryPath" "$info_plist" 2>/dev/null)
      ARM64_DEVICE_DIR="$XCFRAMEWORK/$library_id"
      ARM64_DEVICE_PATH="$ARM64_DEVICE_DIR/$library_path/$NAME"
      is_dynamic=$(file "$ARM64_DEVICE_PATH" | grep -q "dynamically linked" && echo true || echo false)
    fi
  done

  if [ "$found_rosetta_only_sym" = false ]; then
    log 'Good framework, does not require Rosetta simulator'
    return
  fi

  if [ "$found_device_arm64" = false ]; then
    log_error "Missing arm64 symbols for $NAME"
    unfixable_deps+=("$NAME")
    return
  fi

  local x86_64_sim_lipo_output=$(lipo -info "$X86_64_SIMULATOR_PATH" 2>/dev/null)
  if echo "$x86_64_sim_lipo_output" | grep -q 'arm64'; then
      log "$NAME contains arm64 architecture but lacks it in Info.plist. Removing strange arm64 slice from binary."
      lipo -remove arm64 -output "$X86_64_SIMULATOR_PATH" "$X86_64_SIMULATOR_PATH"
  fi

  FRAMEWORK_TYPE=$(if [ "$is_dynamic" = true ]; then echo 'dynamic'; else echo 'static'; fi)
  log "Fixing $NAME ($FRAMEWORK_TYPE)"

  if [ "$is_dynamic" = true ]; then
      add_arm64_sim_to_dynamic
      fixed_dynamic_deps+=("$NAME")
  else
      add_arm64_sim_to_static
      fixed_static_deps+=("$NAME")
  fi

  $PLIST_BUDDY -c "Add :AvailableLibraries:$rosetta_only_sim_index:SupportedArchitectures: string arm64" "$info_plist" 2>/dev/null
  $PLIST_BUDDY -c "Set :AvailableLibraries:$rosetta_only_sim_index:LibraryIdentifier $FAT_ARM64_X86_64_SIMULATOR_ID" "$info_plist"

  log "Added arm64 simulator support to $NAME"
}

add_arm64_sim_to_dynamic() {
  log 'Patching copy of arm64 device executable'
  mkdir "$ARM64_SIMULATOR_DIR"
  cp "$ARM64_DEVICE_PATH" "$ARM64_SIMULATOR_PATH"

  # Used default args from arm64-to-sim sources, format: arm64-to-sim path min_os sdk is_dynamic
  arm64-to-sim "$ARM64_SIMULATOR_PATH" 12 13 true

  make_fat_library
}

add_arm64_sim_to_static() {
  mkdir "$ARM64_SIMULATOR_DIR"
  pushd "$ARM64_SIMULATOR_DIR" >/dev/null
  log 'Unarchiving arm64 binary on .o files'
  ar -x "$ARM64_DEVICE_PATH"
  popd >/dev/null

  for file in "$ARM64_SIMULATOR_DIR"/*.o "$ARM64_SIMULATOR_DIR"/**/*.o; do
    [ -e "$file" ] || continue

    # Used default args from arm64-to-sim sources, format: arm64-to-sim path min_os sdk is_dynamic
    arm64-to-sim "$file" 12 13 false
  done

  log 'Creating arm64 simulator binary from patched arm64 device .o files'
  shopt -s nullglob
  ar crv "$ARM64_SIMULATOR_PATH" "$ARM64_SIMULATOR_DIR"/*.o "$ARM64_SIMULATOR_DIR"/**/*.o

  make_fat_library
}

make_fat_library() {
  log 'Creating fat (x86_64 and arm64) simulator library'

  mkdir "$FAT_ARM64_X86_64_SIMULATOR_DIR"

  lipo -create -output "$FAT_ARM64_X86_64_SIMULATOR_PATH" "$ARM64_SIMULATOR_PATH" "$X86_64_SIMULATOR_PATH"

  rm -rf "$ARM64_SIMULATOR_DIR"
  mv -f "$FAT_ARM64_X86_64_SIMULATOR_PATH" "$X86_64_SIMULATOR_PATH"
  rm -rf "$FAT_ARM64_X86_64_SIMULATOR_DIR"
  mv "$X86_64_SIMULATOR_DIR" "$FAT_ARM64_X86_64_SIMULATOR_DIR"
}

main
