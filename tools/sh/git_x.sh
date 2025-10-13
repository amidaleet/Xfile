#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

function commit {
  git commit "$@"
}

function amend { ## git commit --amend
  git commit --amend "$@"
}

function rebase { ## rebase on passed remote branch
  local BRANCH=${1-develop}

  git fetch origin "$BRANCH"
  git rebase -i "origin/$BRANCH"
}

function push { ## git push
  git push "$@"
}

## main release/ --force
function ff { ## fast-forward reset branch
  local BRANCH=${1-develop}

  if [[ -n $(git status --porcelain) ]]; then
    if read_flags --force -f; then
      log "Force flag used, will reset all changes"
    else
      log_warn "Uncommitted changes, use --force flag to reset them"
      git status --porcelain
      return
    fi
  fi

  git fetch origin "$BRANCH"
  git checkout "$BRANCH"
  git reset --hard "origin/$BRANCH"
}

function feature {
  git checkout -b "feature/$1"
}

function git:ensure_clean { ## Error if git changes found
  fastlane run ensure_git_status_clean \
    show_diff:true
}

function git:number_of_commits { ## Prints number of commits in current branch
  swift "$SWIFT_SCRIPTS_DIR/GetNumberOfCommits.swift"
}

## --staged --commited --all
function git:move_forgotten_files_to_lfs { ## Move files to LFS if needed (convert large files to LFS pointers)
  local files
  local regex=".*\.((?i)png|jpeg|jpg|pdf|webp|psd|7z|br|gz|tar(?-i))$"

  log_info "Force filter files by LFS"

  if read_flags --staged -s; then
    log_info "Filter staged files"
    files="$(git diff --diff-filter=d --name-only --cached | grep -E $regex || true)"
  elif read_flags --commited -c; then
    log_info "Filter files in last commit"
    files="$(git log --diff-filter=d --first-parent --name-only --oneline -n 1 | tail -n +2 | grep -E $regex || true)"
  elif read_flags --all -a; then
    log_info "Filter all files"
    files=.
  else
    log_warn "Option flags unspecified, add some:" \
      "$(task_args git:move_forgotten_files_to_lfs)"
    return 3
  fi

  if [ -z "$files" ]; then
    log_success "LFS filter run is not needed"
    return
  fi

  log_info "Files to filter:" "$files"

  echo "$files" | tr \\n \\0 | xargs -0 git add --renormalize -v

  log_success "LFS filter applied to selected files"
}

## --lose-unstaged-changes
function git:reset_retained_lfs_files { ## Fix LSF error: Encountered X file(s) that should have been pointers, but weren't:
  if ! read_flags --lose-unstaged-changes; then
    log_warn "
    This call will remove all unstaged files!

    1) Use git add to save necessary changes
    2) Call again with --lose-unstaged-changes arg to confirm unstaged diff loss
    "
    return
  fi

  local attributes_backup="$(cat .gitattributes)"

  echo -n "" >.gitattributes

  local files="$(git diff --name-only | grep -v '.gitattributes' || true)"
  log "$files"

  echo "$files" | tr \\n \\0 | xargs -0 git checkout HEAD --
  echo "$attributes_backup" >.gitattributes

  log_success "Pointer-less LFS files must disappear"
}

## --staged --commited
function git:assert_no_snapshot_fail_artifacts { ## Assert no new | diff .png files (returns error code otherwise)
  local files
  local regex="(.*@[0-9]{1}x_(diff|new).png$)|(.*(diff|new)@[0-9]{1}x.png$)"

  log_info "Checking for Snapshot diff/new .png files in stage"

  if read_flags --staged -s; then
    log_info "Filter staged files"
    files="$(git diff --diff-filter=d --name-only --cached | grep -E $regex || true)"
  elif read_flags --commited -c; then
    log_info "Filter files in last commit"
    files="$(git log --diff-filter=d --first-parent --name-only --oneline -n 1 | tail -n +2 | grep -E $regex || true)"
  else
    log_warn "Option flags unspecified, add some:"
    log "$(task_args git:assert_no_snapshot_fail_artifacts)"
    return 3
  fi

  if [ -z "$files" ]; then
    log_success "No snapshot diff/new files"
    return
  else
    log_error "Found unallowed failed snapshot artifacts, please unstage or delete them!"
    log "$files"
    return 3
  fi
}

## --fetch
function git:delete_merged_features { ## Delete branches without upstream in origin (PR must be merged)
  if read_flags --fetch; then
    log_info 'Fetching branches, pruning ones that been removed from remote'
    git fetch origin --prune
  fi

  local merged_features
  local str
  local count

  str="$(\
    git for-each-ref --format '%(refname) %(upstream:track)' refs/heads \
    | grep feature/ \
    | awk '$2 == "[gone]" {sub("refs/heads/", "", $1); print $1}' \
    )"

  str_to_arr "$str" merged_features '\n'

  count="${#merged_features[@]}"

  if [ "$count" -eq 0 ]; then
    log_success 'Merged features not found'
    return
  fi

  log_info 'Found merged features:'
  log "${merged_features[@]}"

  git branch -D "${merged_features[@]}"

  log_success "Removed $count branches"
}

## --fetch
function git:clean_remote { ## Remove too old and merged branches from origin
  if read_flags --fetch -f; then
    log_info "💿 Fetching remote with --prune ..."
    git fetch --prune
  fi

  local branchArr=()
  for branch in $(git branch -r --merged main | grep -v main | grep -v release/ | grep -v cloud/ | sed 's/origin\///'); do
    branchArr+=("$branch")
  done

  if [[ ! "${#branchArr[@]}" -eq 0 ]]; then
    log_info "🗑️  Removing merged branches:"
    for branch in "${branchArr[@]}"; do
      log "$branch"
    done
    git push origin -d "${branchArr[@]}"
  fi

  unset branchArr

  for branch in $(git branch -r | grep -v main | grep -v release/ | grep -v cloud/); do
    if (($(git log -1 --since='2 month ago' -s "$branch" | wc -l) == 0)); then
      branch=$(echo "$branch" | sed 's/origin\///')
      branchArr+=("$branch")
    fi
  done

  if [[ ! "${#branchArr[@]}" -eq 0 ]]; then
    log_info "🗑️  Removing too old branches:"
    for branch in "${branchArr[@]}"; do
      log "$branch"
    done
    git push origin -d "${branchArr[@]}"
  fi

  log_success "Branches clean up finished!"
}

## --fetch --remote --local --wildcard
function git:delete_branches { ## Remove branches by wildcard
  read_opt -w --wildcard WILDCARD
  assert_defined WILDCARD

  if read_flags --fetch -f; then
    log_info "💿 Fetching remote with --prune ..."
    git fetch --prune
  fi

  local branchArr=()

  for branch in $(git branch --all --list "$WILDCARD" | sed 's/  origin\///'); do
    branchArr+=("$branch")
  done

  if [[ ! "${#branchArr[@]}" -eq 0 ]]; then
    log_info "🗑️  Found next branches:"
    for branch in ${branchArr[@]}; do
      log "$branch"
    done
  else
    log_warn "Found no branches to delete!"
  fi

  if read_flags --remote -r; then
    log_info "🗑️  Removing remote branches"
    git push origin -d "${branchArr[@]}"
  fi

  if read_flags --local -l; then
    log_info "🗑️  Removing local branches"
    git branch -d "${branchArr[@]}"
  fi

  log_success "Branches deletion finished!"
}

## --fetch --remote --local --wildcard
function git:delete_tags { ## Remove tags by wildcard
  read_opt -w --wildcard WILDCARD
  assert_defined WILDCARD

  if read_flags --fetch -f; then
    log_info "💿 Fetching remote with --tags ..."
    git fetch --tags --prune
  fi

  local tagsArr=()

  for tag in $(git tag -l "$WILDCARD"); do
    tagsArr+=("$tag")
  done

  if [[ ! "${#tagsArr[@]}" -eq 0 ]]; then
    log_info "🗑️  Found next tags:"
    for tag in ${tagsArr[@]}; do
      log "$tag"
    done
  else
    log_warn "Found no tags to delete!"
  fi

  if read_flags --remote -r; then
    log_info "🗑️  Removing remote tags"
    local refsArr=()
    for tag in ${tagsArr[@]}; do
      refsArr+=("refs/tags/$tag")
    done
    git push -d origin "${refsArr[@]}"
  fi

  if read_flags --local -l; then
    log_info "🗑️  Removing local tags"
    git tag -d "${tagsArr[@]}"
  fi
}

## --branches --from --to
function sync_branches { ## Sync listed branches between 2 remotes
  read_opt -b --branches BRANCHES
  read_opt --from FROM_REMOTE
  read_opt --to TO_REMOTE
  assert_defined BRANCHES FROM_REMOTE TO_REMOTE

  task sync_branches_fetch -b "$BRANCHES" --from "$FROM_REMOTE"
  task sync_branches_push -b "$BRANCHES" --to "$TO_REMOTE"

  log_success "Synchronized '$BRANCHES'!"
}

## --from --branches
function sync_branches_fetch { ## fetch (+ LFS --all) listed branches from remote
  read_opt -b --branches BRANCHES
  read_opt --from FROM_REMOTE
  assert_defined BRANCHES FROM_REMOTE

  log_info "Will fetch '$BRANCHES' from '$FROM_REMOTE'"

  log "Switching from your branch to unlock it's fetching..."
  git switch --detach

  local fetchRefs=''
  for BRANCH in ${BRANCHES[@]}; do
    fetchRefs+=" $BRANCH:$BRANCH"
  done

  log "Fetching refs..."
  git fetch $FROM_REMOTE $fetchRefs

  log "Fetching LFS files..."
  git-lfs fetch --all $FROM_REMOTE $BRANCHES

  log "Switching back to your branch..."
  git switch -

  log_success "Fetched '$BRANCHES' from '$FROM_REMOTE'!"
}

## --to --branches
function sync_branches_push { ## push listed branches to remote
  read_opt -b --branches BRANCHES
  read_opt --to TO_REMOTE
  assert_defined BRANCHES TO_REMOTE

  log_info "Will push '$BRANCHES' to '$TO_REMOTE'"

  log "Pushing refs..."
  git push $TO_REMOTE $BRANCHES

  log_success "Pushed '$BRANCHES' to '$TO_REMOTE'!"
}

begin_xfile_task
