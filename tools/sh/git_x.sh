# shellcheck shell=bash

LFS_FILE=".*\.((?i)jpeg|jpg|png|pdf(?-i))$"

if false; then # Shall not run, it just enables shellcheck impl.sh visibility
  # shellcheck source=./Xfile_source/impl.sh
  source "$GIT_ROOT/Xfile_source/impl.sh"
fi

# ---------- Setup ----------

function setup_git { ## Configure git (hooks, LFS, local config value)
  # Custom git hooks changes hooksPath in local git config.
  # We need to do it before git-lfs setup, because lfs uses hooks too.
  task install_git_hooks

  log_next "Setting local config"
  git config --local lfs.locksverify true

  log_next "Installing git-lfs to local git"
  git lfs install --local --manual 1>/dev/null

  log_next "Loading large files in workspace from LFS"
  git lfs pull
}

function install_git_hooks { ## Install helpful git hooks (LFS, branch name checker, add template commit message)
  if [ "$IS_CI" = true ]; then
    log_info "[CI] Skip installing git hooks for local development"
    git config --local --unset core.hooksPath || log "hooksPath seem to be already removed from local config"
    return 0
  fi

  local current repo_hooks_dir

  repo_hooks_dir="$GIT_ROOT/tools/hooks"
  current=$(git config --local --get core.hooksPath || echo '<not specified in config>')
  log_info "core.hooksPath git config state:" \
    "- In local config:" "$current" \
    "- Repo required hooksPath:" "$repo_hooks_dir"


  if [ "$current" = "$repo_hooks_dir" ]; then
    log_note "No need to change local hooksPath, moving on"
    return 0
  fi

  git config --local --replace-all core.hooksPath "$repo_hooks_dir"
  log_success "Updated local core.hooksPath for repo development"
}

# ---------- Hooks ----------

function pre_commit { ## Run pre-commit hook logic
  task git:move_forgotten_files_to_lfs --staged
  task format_swift
  task lint_swift
}

# ---------- Developer ----------

function fetch { ## fetch указанной ветки без checkout
  local BRANCH=${1-develop}

  git fetch origin "$BRANCH"
}

function rebase { ## rebase на указанную remote ветку
  local BRANCH=${1-develop}

  git fetch origin "$BRANCH"
  git rebase -i "origin/$BRANCH"
}

function commit {
  git commit "$@"
}

function amend { ## Внести staged изменения в текущий коммит, заменив его
  git commit --amend "$@"
}

function push {
  git push "$@"
}

## develop release/ --force
function ff { ## fast forward reset указанной ветки
  local BRANCH=${1-develop}

  if [[ -n $(git status --porcelain) ]]; then
    if read_flags --force -f; then
      log "Force flag used, will reset all changes"
    else
      log_warn "Uncommitted changes, use --force flag to reset them"
      git status --porcelain
      return 0
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
  task fastlane run ensure_git_status_clean \
    show_diff:true
}

function git:number_of_commits { ## Prints number of commits in current branch
  swift "$SWIFT_SCRIPTS_DIR/GetNumberOfCommits.swift"
}

# ---------- Scripts ----------

## --staged --commited --all
function git:move_forgotten_files_to_lfs { ## Перенести ошибочно пропущенные файлы в LFS (превратить картинки в указатели на LFS)
  local files

  log_info "Force filter files by LFS"

  if read_flags --staged -s; then
    log_info "Filter staged files"
    files=$(git diff --diff-filter=d --name-only --cached |  sed -r 's/^"|"$//g' | grep -E "$LFS_FILE" || true)
  elif read_flags --commited -c; then
    log_info "Filter files in last commit"
    files=$(git log --diff-filter=d --first-parent --name-only --oneline -n 1 | tail -n +2 | sed -r 's/^"|"$//g' | grep -E "$LFS_FILE" || true)
  elif read_flags --all -a; then
    log_info "Filter all files"
    files=.
  else
    log_warn "Option flags unspecified, add some:" \
      "$(task_args "${FUNCNAME[0]}")"
    return 3
  fi

  if [ -z "$files" ]; then
    log_success "LFS filter run is not needed"
    return
  fi

  log_info "Files to filter:" \
    "$files"

  printf '%s\n' "$files" | tr \\n \\0 | xargs -0 git add --renormalize -v

  log_success "LFS filter applied to selected files"
}

## --lose-unstaged-changes
function git:reset_retained_lfs_files { ## Убрать неудаляемые LFS файлы (ошибка Encountered 1 file(s) that should have been pointers, but weren't:)
  if ! read_flags --lose-unstaged-changes; then
    log_warn "
    Это деструктивная операция сделает удалит все unstaged файлы.

    Все что нужно сохранить нужно добавить в Stage (git add) либо вовсе закоммитить

    Требуется передать флаг --lose-unstaged-changes в качестве явного подтверждения!
    "
    return
  fi

  local attributes_backup=$(cat .gitattributes)

  echo -n "" >.gitattributes

  local files=$(git diff --name-only | grep -v '.gitattributes' || true)
  log "$files"

  echo "$files" | tr \\n \\0 | xargs -0 git checkout HEAD --
  echo "$attributes_backup" >.gitattributes

  log_success "Битые LFS файлы должны были пропасть"
}

## --staged --commited
function git:assert_no_snapshot_fail_artifacts { ## Проверить отсутствие new и diff .png файлов (вернет код ошибки, если есть)
  local files
  local regex=".*@[0-9]{1}x_(diff|new|merge).png$"

  log_info "Checking for Snapshot diff/new/merge .png files in stage"

  if read_flags --staged -s; then
    log_info "Filter staged files"
    files=$(git diff --diff-filter=d --name-only --cached | grep -E "$regex" || true)
  elif read_flags --commited -c; then
    log_info "Filter files in last commit"
    files=$(git log --diff-filter=d --first-parent --name-only --oneline -n 1 | tail -n +2 | grep -E "$regex" || true)
  else
    log_warn "Option flags unspecified, add some:" \
      "$(task_args "${FUNCNAME[0]}")"
    return 3
  fi

  if [ -z "$files" ]; then
    log_success "No snapshot diff/new/merge files"
    return
  else
    log_error "Found unallowed failed snapshot artifacts, please unstage or delete them!" \
      "$files"
    return 3
  fi
}

## --staged --commited
function git:list_lfs_misplaced_files { ## Вывести файлы (короткие, относительные пути), которые должны быть в LFS, но не там
  forward_out_and_err_to_dir "$OUTPUT_DIR/git_tools/lfs_misplaced_files"

  local misplaced_files_arr=()
  local hard_limit=5242880 # 5 MB

  local git_files_ml_str
  if read_flags --staged -s; then
    git_files_ml_str=$(git diff --diff-filter=d --name-only --cached | sed -r 's/^"|"$//g')
  elif read_flags --commited -c; then
    git_files_ml_str=$(git log --diff-filter=d --first-parent --name-only --oneline -n 1 | tail -n +2 | sed -r 's/^"|"$//g')
  else
    log_warn "Option flags unspecified, add some:" \
      "$(task_args "${FUNCNAME[0]}")"
    return 3
  fi

  local line
  while read -r line; do
    file=$(printf '%s' "$line") # Handle unicode escapes in filenames
    if [ -d "$file" ]; then continue; fi
    local hash=$(git ls-files -s "$file" | cut -d ' ' -f 2)
    local size=$(git cat-file -s "$hash" 2>/dev/null)

    if (( size > hard_limit )) || echo "$file" | grep -qE "$LFS_FILE"; then
      local is_stored_in_lfs=false

      if ! declare -p git_lfs_files >/dev/null 2>&1; then
        str_to_arr "$(git lfs ls-files --name-only)" git_lfs_files '\n'
      fi

      for lfs_file in "${git_lfs_files[@]}"; do
        if [ "$lfs_file" = "$file" ]; then
          is_stored_in_lfs=true
          break
        fi
      done
      if [ ! "$is_stored_in_lfs" = true ]; then
        misplaced_files_arr+=("$file")
      fi
    fi
  done < <(puts "$git_files_ml_str")

  if [ ! "${#misplaced_files_arr[@]}" -eq 0 ]; then
    puts "${misplaced_files_arr[@]}"
  fi
}

## --staged --commited
function git:list_too_large_files { ## Backward compatible legacy for 25.2.1. Use `x list_lfs_misplaced_files`.
  git:list_lfs_misplaced_files "$@"
}

## --fetch
function git:delete_merged_features { ## Удаляем feature/ ветки, у которых более нет upstream копии в origin (должно быть ПР влит)
  if read_flags --fetch; then
    log_info 'Fetching branches, pruning ones that been removed from remote'
    git fetch origin --prune
  fi

  local merged_features str

  str=$(
    git for-each-ref --format '%(refname) %(upstream:track)' refs/heads \
      | grep feature/ \
      | awk '$2 == "[gone]" {sub("refs/heads/", "", $1); print $1}' \
      || true
  )

  if [ -z "$str" ]; then
    log_success 'Merged features not found'
    return 0
  fi

  str_to_arr "$str" merged_features '\n'

  log_info 'Found merged features:' \
    "${merged_features[@]}"

  git branch -D "${merged_features[@]}"

  log_success "Removed ${#merged_features[@]} branches"
}

## --fetch
function git:clean_remote { ## Удалить слишком старые и merged ветки из origin
  if read_flags --fetch -f; then
    log_info "💿 Fetching remote with --prune ..."
    git fetch --prune
  fi

  local branchArr=() branch
  for branch in $(git branch -r --merged develop | grep -v develop | grep -v release/ | grep -v cloud/ | sed 's/origin\///'); do
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

  for branch in $(git branch -r | grep -v develop | grep -v release/ | grep -v cloud/); do
    if [ "$(git log -1 --since='2 month ago' -s "$branch" | wc -l)" -eq 0 ]; then
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
function git:delete_branches { ## Удалить ветки по wildcard
  local WILDCARD branch
  read_opt -w --wildcard WILDCARD
  assert_defined WILDCARD

  if read_flags --fetch -f; then
    log_info "💿 Fetching remote with --prune ..."
    git fetch --prune
  fi

  local branchArr=() branch

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
function git:delete_tags { ## Удалить tags по wildcard
  local WILDCARD tag
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

# ---------- Cloud <-> Sigma Sync ----------

## --branches --from --to --fetch_only --push_only
function sync_branches { ## Синхронизировать несколько веток сразу между 2-мя remote (Cloud & Sigma)
  local BRANCHES FROM_REMOTE TO_REMOTE
  read_opt -b --branches BRANCHES
  read_opt --from FROM_REMOTE
  read_opt --to TO_REMOTE
  assert_defined BRANCHES FROM_REMOTE TO_REMOTE

  if read_flags --fetch_only; then
    task sync_branches_fetch -b "$BRANCHES" --from "$FROM_REMOTE"
    return 0
  elif read_flags --push_only; then
    task sync_branches_push -b "$BRANCHES" --to "$TO_REMOTE"
    return 0
  else
    task sync_branches_fetch -b "$BRANCHES" --from "$FROM_REMOTE"
    task sync_branches_push -b "$BRANCHES" --to "$TO_REMOTE"
  fi

  log_success "Synchronized '$BRANCHES'!"
}

## --from --branches
function sync_branches_fetch { ## fetch (+ LFS --all) несколько веток сразу между с указанного remote
  local BRANCHES FROM_REMOTE BRANCH
  read_opt -b --branches BRANCHES
  read_opt --from FROM_REMOTE
  assert_defined BRANCHES FROM_REMOTE

  log_info "Will fetch '$BRANCHES' from '$FROM_REMOTE'"

  log "Switching from your branch to unlock it's fetching..."
  git switch --detach

  str_to_arr "$BRANCHES" BRANCHES ' '

  local fetchRefs=()
  for BRANCH in "${BRANCHES[@]}"; do
    fetchRefs+=("$BRANCH:$BRANCH")
  done

  log "Fetching refs..."
  git fetch "$FROM_REMOTE" "${fetchRefs[@]}"

  log "Fetching LFS files..."
  git-lfs fetch --all "$FROM_REMOTE" "${BRANCHES[@]}"

  log "Switching back to your branch..."
  git switch -

  log_success "Fetched from '$FROM_REMOTE', branches:" "${BRANCHES[@]}"
}

## --to --branches
function sync_branches_push { ## push нескольких веток сразу в указанный remote
  local BRANCHES TO_REMOTE
  read_opt -b --branches BRANCHES
  read_opt --to TO_REMOTE
  assert_defined BRANCHES TO_REMOTE

  log_info "Will push '$BRANCHES' to '$TO_REMOTE'"

  str_to_arr "$BRANCHES" BRANCHES ' '

  log "Pushing refs..."
  git push "$TO_REMOTE" "${BRANCHES[@]}"

  log_success "Pushed to '$TO_REMOTE', branches:" "${BRANCHES[@]}"
}

