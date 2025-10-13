#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

## --name
function job_get_script { ## GET request, loads config.xml for Jenkins Job
  read_opt --name job_name
  assert_defined job_name jenkins_creds

  log_info "Loading script for $job_name"

  curl "$X_JENKINS_JOB_LIST_URL/${job_name}/config.xml" \
    -u "$jenkins_creds" \
    -o "$X_JENKINS_JOB_CONFIGS_DIR/${job_name}.xml" \
    --show-error \
    --fail

  log_success "Loaded script for $job_name"
}

## --name
function job_post_script { ## POST request, updates config.xml for Jenkins Job
  read_opt --name job_name
  assert_defined job_name jenkins_creds

  log_info "Updating script for $job_name"

  # With application/xml type server returns code 500
  curl "$X_JENKINS_JOB_LIST_URL/${job_name}/config.xml" \
    -X POST \
    -u "$jenkins_creds" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$X_JENKINS_JOB_CONFIGS_DIR/$job_name.xml" \
    --fail \
    --show-error

  log_success "Updated script for $job_name"
}

## --local --remote
function job_pull { ## Load Jenkins Job config, replace local repo script with loaded one
  read_opt --local job_source_file_name
  read_opt --remote job_remote_name
  assert_defined job_source_file_name job_remote_name

  log_info "Pulling script from server job $job_remote_name to $job_source_file_name.groovy"

  task job_get_script --name "$job_remote_name"
  ruby_run "$RUBY_SCRIPTS_DIR/job_script_reader.rb" "$job_remote_name" \
    > "$X_JENKINS_JOB_SCRIPTS_DIR/$job_source_file_name.groovy"

  log_success "Put server code to $job_source_file_name.groovy"
}

## --local --remote
function job_push { ## Load Jenkins Job config, replace script with repo version, send back
  read_opt --local job_source_file_name
  read_opt --remote job_remote_name
  assert_defined job_source_file_name job_remote_name

  log_info "Pushing script from $job_source_file_name.groovy to server job $job_remote_name"

  task jenkins_job_get_script --name "$job_remote_name"
  ruby_run "$RUBY_SCRIPTS_DIR/job_script_writer.rb" "$job_source_file_name" "$job_remote_name"
  task job_post_script --name "$job_remote_name"

  log_success "Put local code to server job $job_remote_name"
}

## --to_remote --to_local
function job_sync { ## Update Jobs code in repo <-> server
  export X_JENKINS_JOB_SCRIPTS_DIR="devops/jobs"
  export X_JENKINS_JOB_CONFIGS_DIR="output/xml_configs/devops"
  export X_JENKINS_JOB_LIST_URL="https://sample.com/job/repo_folder/job"

  if [ -z "$jenkins_creds" ]; then
    log_error "Missing token"
    log_warn "Export job admin token, like:" \
      "export jenkins_creds='login:token'"
    exit 3
  fi

  rm -rf "$X_JENKINS_JOB_CONFIGS_DIR"
  mkdir -p "$X_JENKINS_JOB_CONFIGS_DIR"

  if read_flags --to_remote; then
    local cmd="job_push"
  elif read_flags --to_local; then
    local cmd="job_pull"
  else
    log_error "Missing required destination arg!"
    exit 3
  fi

  task "$cmd" --local DebugJob --remote Debug_Job
}

begin_xfile_task
