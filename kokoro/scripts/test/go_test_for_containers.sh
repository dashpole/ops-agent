#!/bin/bash
# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# This script needs the following environment variables to be defined:
# 1. various KOKORO_* variables
# 2. TEST_SUITE_NAME: name of the test file, minus the .go suffix. For example,
#    ops_agent_test or third_party_apps_test.
#
# And also the following, documented at the top of gce_testing.go and
# $TEST_SUITE_NAME.go:
# 1. PROJECT
# 2. ZONE
# 3. TRANSFERS_BUCKET
#
# If TEST_SOURCE_PIPER_LOCATION is defined, this script will look for test
# sources in there, otherwise it will look in GitHub.
#
# In addition, the following test suites need additional env variables:
# install_scripts_test:
#   * AGENTS_TO_TEST: comma-separated list of agents to test.
#   * SCRIPTS_DIR: path to installation scripts to test.
# os_config_test:
#   * GCLOUD_LITE_BLAZE_PATH: path to just-built copy of gcloud_lite to use for
#     testing.

set -e
set -u
set -x
set -o pipefail

# cd to the root of the git repo containing this script ($0).
cd "$(readlink -f "$(dirname "$0")")"
cd ../../../

# Source the common utilities, for track_flakiness.
source kokoro/scripts/utils/common.sh

track_flakiness

# Avoids "fatal: detected dubious ownership in repository" errors on Kokoro containers.
git config --global --add safe.directory ...

# If a built agent was passed in from Kokoro directly, use that.
if compgen -G "${KOKORO_GFILE_DIR}/result/google-cloud-ops-agent*" > /dev/null; then
  # Upload the agent packages to GCS.
  AGENT_PACKAGES_IN_GCS="gs://${TRANSFERS_BUCKET}/agent_packages/${KOKORO_BUILD_ID}"
  gsutil cp -r "${KOKORO_GFILE_DIR}/result/*" "${AGENT_PACKAGES_IN_GCS}/"

  # AGENT_PACKAGES_IN_GCS is used to tell Ops Agent integration tests
  # (https://github.com/GoogleCloudPlatform/ops-agent/tree/master/integration_test)
  # to install and use this custom build of the agent instead.
  export AGENT_PACKAGES_IN_GCS
fi

LOGS_DIR="${KOKORO_ARTIFACTS_DIR}/logs"
mkdir -p "${LOGS_DIR}"

if [[ -n "${TEST_SOURCE_PIPER_LOCATION-}" ]]; then
  if [[ -n "${SCRIPTS_DIR-}" ]]; then
    SCRIPTS_DIR="${KOKORO_PIPER_DIR}/${SCRIPTS_DIR}"
    export SCRIPTS_DIR
  fi

  cd "${KOKORO_PIPER_DIR}/${TEST_SOURCE_PIPER_LOCATION}/${TEST_SUITE_NAME}"

  # Make a module containing the latest dependencies from GitHub.
  go mod init "${TEST_SUITE_NAME}"
  go get github.com/GoogleCloudPlatform/ops-agent@master
  go mod tidy -compat=${GO_VERSION}
else
  cd integration_test
fi

if [[ "${TEST_SUITE_NAME}" == "os_config_test" ]]; then
  GCLOUD_TO_TEST="${KOKORO_BLAZE_DIR}/${GCLOUD_LITE_BLAZE_PATH}"
  export GCLOUD_TO_TEST
fi

STDERR_STDOUT_FILE="${KOKORO_ARTIFACTS_DIR}/test_stderr_stdout.txt"
function produce_xml() {
  cat "${STDERR_STDOUT_FILE}" | "$(go env GOPATH)/bin/go-junit-report" -parser gojson > "${LOGS_DIR}/sponge_log.xml"
}
# Always run produce_xml on exit, whether the test passes or fails.
trap produce_xml EXIT

# Boost the max number of open files from 1024 to 1 million.
ulimit -n 1000000

# Set up some command line flags for "go test".
args=(
  -json
  -test.parallel=1000
  -tags=integration_test
  -timeout=3h
)
if [[ "${SHORT:-false}" == "true" ]]; then
  args+=( "-test.short" )
fi

TEST_UNDECLARED_OUTPUTS_DIR="${LOGS_DIR}" \
  go test -v "${TEST_SUITE_NAME}.go" \
  "${args[@]}" \
  2>&1 \
  | tee "${STDERR_STDOUT_FILE}"