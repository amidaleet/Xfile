#!/usr/bin/env bash

set -eo pipefail

source "$GIT_ROOT/Xfile_source/impl.sh"

link_child_xfile "$GIT_ROOT/Xfile"

## --to_remote --to_local
function jenkins_sync_jobs { ## Update Jobs code in repo <-> cloud server
  export X_JENKINS_JOB_SCRIPTS_DIR="devops/jobs"
  export X_JENKINS_JOB_CONFIGS_DIR="$OUTPUT_DIR/xml_configs/jenkins"
  export X_JENKINS_JOB_LIST_URL="https://sample.com/job/repo_folder/job"

  if [ -z "$jenkins_creds_cloud" ]; then
    log_error "Не найден токен для запросов jenkins"
    log_warn "Нужен экспорт токена перед вызовом команды, формат ниже:" \
      "export jenkins_creds_cloud='login:token'"
    exit 3
  fi
  export jenkins_creds=$jenkins_creds_cloud

  rm -rf "$X_JENKINS_JOB_CONFIGS_DIR"
  mkdir -p "$X_JENKINS_JOB_CONFIGS_DIR"

  local cmd
  if read_flags --to_remote; then
    cmd="job_push"
  elif read_flags --to_local; then
    cmd="job_pull"
  else
    log_error "Missing required destination arg!"
    exit 3
  fi

  task "$cmd" --local DebugJob --remote Debug_Job
}

## --name
job_get_script() { ## GET request, loads config.xml for Jenkins Job
  local job_name
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
job_post_script() { ## POST request, updates config.xml for Jenkins Job
  local job_name
  read_opt --name job_name
  assert_defined job_name jenkins_creds

  log_info "Updating script for $job_name"

  # с application/xml получаем 500 код
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
job_pull() { ## Load Jenkins Job config, replace local repo script with loaded one
  local job_source_file_name job_remote_name
  read_opt --local job_source_file_name
  read_opt --remote job_remote_name
  assert_defined job_source_file_name job_remote_name

  log_info "Pulling script from server job $job_remote_name to $job_source_file_name.groovy"

  task job_get_script --name "$job_remote_name"
  task ruby_run "$RUBY_SCRIPTS_DIR/job_script_reader.rb" "$job_remote_name" \
    >"$X_JENKINS_JOB_SCRIPTS_DIR/$job_source_file_name.groovy"

  log_success "Put server code to $job_source_file_name.groovy"
}

## --local --remote
job_push() { ## Load Jenkins Job config, replace script with repo version, send back
  local job_source_file_name job_remote_name
  read_opt --local job_source_file_name
  read_opt --remote job_remote_name
  assert_defined job_source_file_name job_remote_name

  log_info "Pushing script from $job_source_file_name.groovy to server job $job_remote_name"

  task job_get_script --name "$job_remote_name"
  task ruby_run "$RUBY_SCRIPTS_DIR/job_script_writer.rb" "$job_source_file_name" "$job_remote_name"
  task job_post_script --name "$job_remote_name"

  log_success "Put local code to server job $job_remote_name"
}

begin_xfile_task
