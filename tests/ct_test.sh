#!/usr/bin/env bash

# Failure-path tests for ct.sh.
#
# curl, cosign and uv are stubbed so the script's control flow can be exercised
# without network access. The happy path against the real tools is already
# covered end to end by the jobs in .github/workflows/test-action.yml; what is
# tested here is everything that fails, because those paths fail silently --
# a regression that stops invoking cosign would otherwise leave CI green.

set -o errexit
set -o nounset
set -o pipefail

CT_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ct.sh"

passes=0
failures=0

pass() {
    printf 'ok   - %s\n' "$1"
    passes=$((passes + 1))
}

fail() {
    printf 'FAIL - %s\n       %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
}

# Fresh sandbox per test: stub PATH entry, tool cache, and the runner files
# that ct.sh appends to.
setup() {
    workdir="$(mktemp -d)"
    stubdir="${workdir}/bin"
    mkdir -p "${stubdir}" "${workdir}/cache" "${workdir}/tmp"

    export RUNNER_TOOL_CACHE="${workdir}/cache"
    export GITHUB_PATH="${workdir}/github_path"
    export GITHUB_ENV="${workdir}/github_env"
    : > "${GITHUB_PATH}"
    : > "${GITHUB_ENV}"

    # A real tarball, so tar and the post-extract steps behave normally.
    mkdir -p "${workdir}/payload/etc"
    printf '#!/bin/sh\necho "Version: v3.14.0"\n' > "${workdir}/payload/ct"
    chmod +x "${workdir}/payload/ct"
    echo 'schema' > "${workdir}/payload/etc/chart_schema.yaml"
    tar -czf "${workdir}/release.tar.gz" -C "${workdir}/payload" .

    stub_curl_ok
    stub_cosign 0
    printf '#!/bin/sh\nexit 0\n' > "${stubdir}/uv"
    chmod +x "${stubdir}/uv"
}

teardown() {
    rm -rf "${workdir}"
}

stub_curl_ok() {
    cat > "${stubdir}/curl" <<EOF
#!/bin/sh
out=""
while [ \$# -gt 0 ]; do
    case "\$1" in
        -sSLo|-o) out="\$2"; shift ;;
    esac
    shift
done
cp "${workdir}/release.tar.gz" "\${out}"
EOF
    chmod +x "${stubdir}/curl"
}

stub_curl_http_error() {
    # curl --fail exits 22 on an HTTP error and writes no output file.
    printf '#!/bin/sh\nexit 22\n' > "${stubdir}/curl"
    chmod +x "${stubdir}/curl"
}

stub_cosign() {
    cat > "${stubdir}/cosign" <<EOF
#!/bin/sh
echo invoked >> "${workdir}/cosign.log"
exit $1
EOF
    chmod +x "${stubdir}/cosign"
}

cosign_invoked() {
    [[ -f "${workdir}/cosign.log" ]]
}

# Runs ct.sh with the stubs first on PATH. Never aborts the suite: the exit
# status is what most of these tests assert on.
#
# TMPDIR is set for this invocation only, so ct.sh's staging directory lands
# somewhere observable without leaking into the harness's own mktemp calls.
# Note GNU mktemp honours TMPDIR but BSD mktemp does not, so the staging-dir
# assertion is only meaningful on Linux, which is where CI runs it.
run_ct() {
    set +o errexit
    TMPDIR="${workdir}/tmp" PATH="${stubdir}:${PATH}" \
        bash "${CT_SH}" "$@" > "${workdir}/output" 2>&1
    rc=$?
    set -o errexit
}

output() {
    cat "${workdir}/output"
}

#-----------------------------------------------------------------------------
# A version string that is not a plain version number must be rejected before
# it can reach a filesystem path or the $GITHUB_PATH / $GITHUB_ENV files.
#-----------------------------------------------------------------------------

test_rejects_hostile_versions() {
    local name value
    while IFS='|' read -r name value; do
        [[ -n "${name}" ]] || continue
        setup
        # Precondition for the traversal case: a previous run leaves ct/ behind.
        mkdir -p "${RUNNER_TOOL_CACHE}/ct"
        run_ct --version "${value}"

        if [[ ${rc} -eq 0 ]]; then
            fail "rejects ${name}" "expected non-zero exit, got 0"
        elif ! output | grep -q 'must be a version number'; then
            fail "rejects ${name}" "expected a validation error, got: $(output | tail -1)"
        elif cosign_invoked; then
            fail "rejects ${name}" "cosign should not have been reached"
        elif [[ -s "${GITHUB_PATH}" || -s "${GITHUB_ENV}" ]]; then
            fail "rejects ${name}" "runner files were written to"
        else
            pass "rejects ${name}"
        fi
        teardown
    done <<'CASES'
path traversal|../../../../tmp/evil
absolute path|/tmp/evil
command substitution|3.14.0$(id)
semicolon|3.14.0; id
CASES

    # Newline kept out of the heredoc above, which is line-oriented.
    setup
    run_ct --version "$(printf '3.14.0\nLD_PRELOAD=/tmp/evil.so')"
    if [[ ${rc} -eq 0 ]]; then
        fail "rejects embedded newline" "expected non-zero exit, got 0"
    elif grep -q 'LD_PRELOAD' "${GITHUB_ENV}"; then
        fail "rejects embedded newline" "injected a variable into \$GITHUB_ENV"
    else
        pass "rejects embedded newline"
    fi
    teardown
}

# The action passes v-prefixed versions (test-action.yml uses 'v3.8.0'), so the
# leading v must still be stripped and accepted.
test_accepts_v_prefixed_version() {
    setup
    run_ct --version v3.14.0
    if [[ ${rc} -ne 0 ]]; then
        fail "accepts v-prefixed version" "exit ${rc}: $(output | tail -1)"
    else
        pass "accepts v-prefixed version"
    fi
    teardown
}

test_accepts_prerelease_version() {
    setup
    run_ct --version 3.14.0-rc.1
    if [[ ${rc} -ne 0 ]] && output | grep -q 'must be a version number'; then
        fail "accepts prerelease version" "rejected 3.14.0-rc.1"
    else
        pass "accepts prerelease version"
    fi
    teardown
}

#-----------------------------------------------------------------------------
# A directory left behind by an earlier failed run must not be mistaken for a
# verified install.
#-----------------------------------------------------------------------------

test_stale_cache_dir_does_not_skip_verification() {
    setup
    # Exactly what a run that died after mkdir but before extraction leaves.
    mkdir -p "${RUNNER_TOOL_CACHE}/ct/3.14.0/amd64"
    run_ct --version 3.14.0

    if ! cosign_invoked; then
        fail "stale cache dir does not skip verification" \
            "cosign was never invoked (verification silently skipped)"
    elif [[ ${rc} -ne 0 ]]; then
        fail "stale cache dir does not skip verification" "exit ${rc}: $(output | tail -1)"
    else
        pass "stale cache dir does not skip verification"
    fi
    teardown
}

test_failed_verification_leaves_nothing_reusable() {
    setup
    stub_cosign 1
    run_ct --version 3.14.0

    local leftovers
    leftovers="$(find "${RUNNER_TOOL_CACHE}" -mindepth 1 | wc -l | tr -d ' ')"

    if [[ ${rc} -eq 0 ]]; then
        fail "failed verification leaves nothing reusable" "expected non-zero exit, got 0"
    elif ! output | grep -q 'Unable to validate chart-testing version'; then
        fail "failed verification leaves nothing reusable" \
            "expected the validation error, got: $(output | tail -1)"
    elif [[ "${leftovers}" != "0" ]]; then
        fail "failed verification leaves nothing reusable" \
            "${leftovers} entries left under the tool cache"
    elif [[ -s "${GITHUB_PATH}" ]]; then
        fail "failed verification leaves nothing reusable" "\$GITHUB_PATH was written to"
    else
        pass "failed verification leaves nothing reusable"
    fi
    teardown
}

test_staging_dir_is_always_cleaned_up() {
    setup
    stub_cosign 1
    run_ct --version 3.14.0

    local leaked
    leaked="$(find "${workdir}/tmp" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
    if [[ "${leaked}" != "0" ]]; then
        fail "staging dir is always cleaned up" "${leaked} staging dir(s) left in TMPDIR"
    else
        pass "staging dir is always cleaned up"
    fi
    teardown
}

#-----------------------------------------------------------------------------
# A download failure must not be reported as a signature problem.
#-----------------------------------------------------------------------------

test_download_failure_is_distinct_from_verification_failure() {
    setup
    stub_curl_http_error
    run_ct --version 3.14.0

    if [[ ${rc} -eq 0 ]]; then
        fail "download failure is reported as such" "expected non-zero exit, got 0"
    elif ! output | grep -q 'Unable to download chart-testing version'; then
        fail "download failure is reported as such" \
            "expected a download error, got: $(output | tail -1)"
    else
        pass "download failure is reported as such"
    fi
    teardown
}

#-----------------------------------------------------------------------------
# The success path must still install and publish the tool.
#-----------------------------------------------------------------------------

test_successful_install() {
    setup
    run_ct --version 3.14.0

    local ct_bin="${RUNNER_TOOL_CACHE}/ct/3.14.0/amd64/ct"
    if [[ ${rc} -ne 0 ]]; then
        fail "successful install" "exit ${rc}: $(output | tail -1)"
    elif ! cosign_invoked; then
        fail "successful install" "cosign was not invoked"
    elif [[ ! -x "${ct_bin}" ]]; then
        fail "successful install" "ct binary missing at ${ct_bin}"
    elif ! grep -qx "${RUNNER_TOOL_CACHE}/ct/3.14.0/amd64" "${GITHUB_PATH}"; then
        fail "successful install" "cache dir was not added to \$GITHUB_PATH"
    elif ! grep -q '^CT_CONFIG_DIR=' "${GITHUB_ENV}"; then
        fail "successful install" "CT_CONFIG_DIR was not exported"
    else
        pass "successful install"
    fi
    teardown
}

test_missing_tool_cache_is_an_error() {
    setup
    export RUNNER_TOOL_CACHE="${workdir}/does-not-exist"
    run_ct --version 3.14.0
    if [[ ${rc} -eq 0 ]]; then
        fail "missing tool cache is an error" "expected non-zero exit, got 0"
    else
        pass "missing tool cache is an error"
    fi
    teardown
}

main() {
    test_rejects_hostile_versions
    test_accepts_v_prefixed_version
    test_accepts_prerelease_version
    test_stale_cache_dir_does_not_skip_verification
    test_failed_verification_leaves_nothing_reusable
    test_staging_dir_is_always_cleaned_up
    test_download_failure_is_distinct_from_verification_failure
    test_successful_install
    test_missing_tool_cache_is_an_error

    printf '\n%d passed, %d failed\n' "${passes}" "${failures}"
    [[ ${failures} -eq 0 ]]
}

main "$@"
