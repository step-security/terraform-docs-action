#!/usr/bin/env bash
#
# Copyright 2021 The terraform-docs Authors.
# Copyright 2025 Step Security.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o pipefail
set -o errtrace

# shellcheck disable=SC2206
cmd_args=(${INPUT_OUTPUT_FORMAT})

# shellcheck disable=SC2206
cmd_args+=(${INPUT_ARGS})

REPO_PRIVATE=$(jq -r '.repository.private | tostring' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
UPSTREAM="terraform-docs/gh-actions"
ACTION_REPO="${GITHUB_ACTION_REPOSITORY:-}"
DOCS_URL="https://docs.stepsecurity.io/actions/stepsecurity-maintained-actions"

echo ""
echo -e "\033[1;36mStepSecurity Maintained Action\033[0m"
echo "Secure drop-in replacement for $UPSTREAM"
if [ "$REPO_PRIVATE" = "false" ]; then
  echo -e "\033[32m✓ Free for public repositories\033[0m"
fi
echo -e "\033[36mLearn more:\033[0m $DOCS_URL"
echo ""

if [ "$REPO_PRIVATE" != "false" ]; then
  SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"

  if [ "$SERVER_URL" != "https://github.com" ]; then
    BODY=$(printf '{"action":"%s","ghes_server":"%s"}' "$ACTION_REPO" "$SERVER_URL")
  else
    BODY=$(printf '{"action":"%s"}' "$ACTION_REPO")
  fi

  API_URL="https://agent.api.stepsecurity.io/v1/github/$GITHUB_REPOSITORY/actions/maintained-actions-subscription"

  RESPONSE=$(curl --max-time 3 -s -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "$API_URL" -o /dev/null) && CURL_EXIT_CODE=0 || CURL_EXIT_CODE=$?

  if [ "$CURL_EXIT_CODE" -ne 0 ]; then
    echo "Timeout or API not reachable. Continuing to next step."
  elif [ "$RESPONSE" = "403" ]; then
    echo -e "::error::\033[1;31mThis action requires a StepSecurity subscription for private repositories.\033[0m"
    echo -e "::error::\033[31mLearn how to enable a subscription: $DOCS_URL\033[0m"
    exit 1
  fi
fi

if [ "${INPUT_CONFIG_FILE}" = "disabled" ]; then
    case "$INPUT_OUTPUT_FORMAT" in
    "asciidoc" | "asciidoc table" | "asciidoc document")
        cmd_args+=(--indent "${INPUT_INDENTION}")
        ;;

    "markdown" | "markdown table" | "markdown document")
        cmd_args+=(--indent "${INPUT_INDENTION}")
        ;;
    esac

    if [ -z "${INPUT_TEMPLATE}" ]; then
        INPUT_TEMPLATE=$(printf '<!-- BEGIN_TF_DOCS -->\n{{ .Content }}\n<!-- END_TF_DOCS -->')
    fi
fi

if [ -z "${INPUT_GIT_PUSH_USER_NAME}" ]; then
    INPUT_GIT_PUSH_USER_NAME="github-actions[bot]"
fi

if [ -z "${INPUT_GIT_PUSH_USER_EMAIL}" ]; then
    INPUT_GIT_PUSH_USER_EMAIL="github-actions[bot]@users.noreply.github.com"
fi

if [ -n "${INPUT_GIT_SUB_DIR}" ]; then
    GITHUB_WORKSPACE="${GITHUB_WORKSPACE}/${INPUT_GIT_SUB_DIR}"
    echo "Using non-standard GITHUB_WORKSPACE of ${GITHUB_WORKSPACE}"
fi

git_setup() {
    # When the runner maps the $GITHUB_WORKSPACE mount, it is owned by the runner
    # user while the created folders are owned by the container user, causing this
    # error. Issue description here: https://github.com/actions/checkout/issues/766
    git config --global --add safe.directory "${GITHUB_WORKSPACE}"

    git config --global user.name "${INPUT_GIT_PUSH_USER_NAME}"
    git config --global user.email "${INPUT_GIT_PUSH_USER_EMAIL}"
    git fetch --depth=1 origin +refs/tags/*:refs/tags/* || true
}

git_add() {
    local file
    file="$1"
    git add "${file}"
    if [ "$(git status --porcelain | grep "$file" | grep -c -E '([MA]\W).+')" -eq 1 ]; then
        echo "::debug Added ${file} to git staging area"
    else
        echo "::debug No change in ${file} detected"
    fi
}

git_status() {
    git status --porcelain | grep -c -E '([MA]\W).+' || true
}

git_commit() {
    if [ "$(git_status)" -eq 0 ]; then
        echo "::debug No files changed, skipping commit"
        exit 0
    fi

    echo "::debug Following files will be committed"
    git status -s

    local args=(
        -m "${INPUT_GIT_COMMIT_MESSAGE}"
    )

    if [ "${INPUT_GIT_PUSH_SIGN_OFF}" = "true" ]; then
        args+=("-s")
    fi

    git commit "${args[@]}"
}

update_doc() {
    local working_dir
    working_dir="$1"
    echo "::debug working_dir=${working_dir}"

    local exec_args
    exec_args=( "${cmd_args[@]}" )

    if [ -n "${INPUT_CONFIG_FILE}" ] && [ "${INPUT_CONFIG_FILE}" != "disabled" ]; then
        local config_file

        if [ -f "${INPUT_CONFIG_FILE}" ]; then
            config_file="${INPUT_CONFIG_FILE}"
        else
            config_file="${working_dir}/${INPUT_CONFIG_FILE}"
        fi

        echo "::debug config_file=${config_file}"
        exec_args+=(--config "${config_file}")
    fi

    if [ "${INPUT_OUTPUT_METHOD}" == "inject" ] || [ "${INPUT_OUTPUT_METHOD}" == "replace" ]; then
        echo "::debug output_mode=${INPUT_OUTPUT_METHOD}"
        exec_args+=(--output-mode "${INPUT_OUTPUT_METHOD}")

        echo "::debug output_file=${INPUT_OUTPUT_FILE}"
        exec_args+=(--output-file "${INPUT_OUTPUT_FILE}")
    fi

    if [ -n "${INPUT_TEMPLATE}" ]; then
        exec_args+=(--output-template "${INPUT_TEMPLATE}")
    fi

    if [ "${INPUT_RECURSIVE}" = "true" ]; then
        if [ -n "${INPUT_RECURSIVE_PATH}" ]; then
            exec_args+=(--recursive)
            exec_args+=(--recursive-path "${INPUT_RECURSIVE_PATH}")
        fi
    fi

    exec_args+=("${working_dir}")

    local success

    echo "::debug terraform-docs" "${exec_args[@]}"
    terraform-docs "${exec_args[@]}"
    success=$?

    if [ $success -ne 0 ]; then
        exit $success
    fi

    if [ "${INPUT_OUTPUT_METHOD}" == "inject" ] || [ "${INPUT_OUTPUT_METHOD}" == "replace" ]; then
        git_add "${working_dir}/${OUTPUT_FILE}"
    fi
}

# go to github repo
cd "${GITHUB_WORKSPACE}"

git_setup

if [ -f "${GITHUB_WORKSPACE}/${INPUT_ATLANTIS_FILE}" ]; then
    # Parse an atlantis yaml file
    for line in $(yq e '.projects[].dir' "${GITHUB_WORKSPACE}/${INPUT_ATLANTIS_FILE}"); do
        update_doc "${line//- /}"
    done
elif [ -n "${INPUT_FIND_DIR}" ] && [ "${INPUT_FIND_DIR}" != "disabled" ]; then
    # Find all tf
    for project_dir in $(find "${INPUT_FIND_DIR}" -name '*.tf' -exec dirname {} \; | uniq); do
        update_doc "${project_dir}"
    done
else
    # Split INPUT_WORKING_DIR by commas
    for project_dir in ${INPUT_WORKING_DIR//,/ }; do
        update_doc "${project_dir}"
    done
fi

# always set num_changed output
set +e
num_changed=$(git_status)
set -e
echo "num_changed=${num_changed}" >> "$GITHUB_OUTPUT"

if [ "${INPUT_GIT_PUSH}" = "true" ]; then
    git_commit
    git push
else
    if [ "${INPUT_FAIL_ON_DIFF}" = "true" ] && [ "${num_changed}" -ne 0 ]; then
        echo "::error ::Uncommitted change(s) has been found!"
        exit 1
    fi
fi

exit 0
