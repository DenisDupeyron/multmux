#!/usr/bin/env bats
# Unit tests for version_gt and fetch_latest_version. fetch_latest_version
# is tested here with stubbed curl/wget binaries (no real network), so it
# runs fast and covers failure modes real network flakiness would make
# hard to reproduce on demand: missing tools, empty/malformed responses,
# and simulated timeouts/failures.

setup() {
    load '../helpers/common'
    mm_set_fake_home
    mm_source
}

# --- version_gt ---

@test "version_gt: equal versions are not greater" {
    run version_gt "1.2.3" "1.2.3"
    [ "${status}" -ne 0 ]
}

@test "version_gt: a simple patch bump is greater" {
    run version_gt "1.2.4" "1.2.3"
    [ "${status}" -eq 0 ]
}

@test "version_gt: a simple patch downgrade is not greater" {
    run version_gt "1.2.2" "1.2.3"
    [ "${status}" -ne 0 ]
}

@test "version_gt: numeric (not lexicographic) comparison of multi-digit segments" {
    # Lexicographic comparison would wrongly say "1.9.0" > "1.10.0".
    run version_gt "1.10.0" "1.9.0"
    [ "${status}" -eq 0 ]
    run version_gt "1.9.0" "1.10.0"
    [ "${status}" -ne 0 ]
}

@test "version_gt: a major version bump beats any minor/patch difference" {
    run version_gt "2.0.0" "1.99.99"
    [ "${status}" -eq 0 ]
}

# --- fetch_latest_version: helpers to stub curl/wget on PATH ---

mm_stub_tool() {
    # $1 = tool name (curl/wget), $2 = shell body of the fake tool
    local stubdir="${BATS_TEST_TMPDIR}/stubbin"
    mkdir -p "${stubdir}"
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "${stubdir}/$1"
    chmod +x "${stubdir}/$1"
    export PATH="${stubdir}:${PATH}"
}

@test "fetch_latest_version: parses VERSION out of a successful curl response" {
    mm_stub_tool curl 'echo '"'"'VERSION="9.9.9"'"'"''
    result="$(fetch_latest_version 3)"
    [ "${result}" = "9.9.9" ]
}

@test "fetch_latest_version: falls back to wget when curl is unavailable" {
    mm_hermetic_path_without curl
    local stubdir="${BATS_TEST_TMPDIR}/hermetic-bin"
    cat > "${stubdir}/wget" << 'STUB'
#!/usr/bin/env bash
echo 'VERSION="8.8.8"'
STUB
    chmod +x "${stubdir}/wget"
    ! command -v curl &>/dev/null
    result="$(fetch_latest_version 3)"
    [ "${result}" = "8.8.8" ]
}

@test "fetch_latest_version: prints nothing (no error) when neither curl nor wget exists" {
    mm_hermetic_path_without curl wget
    ! command -v curl &>/dev/null
    ! command -v wget &>/dev/null
    run fetch_latest_version 3
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "fetch_latest_version: prints nothing when the response has no VERSION line" {
    mm_stub_tool curl 'echo "not a multmux script at all"'
    run fetch_latest_version 3
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "fetch_latest_version: prints nothing when the response is empty (offline/timeout simulated)" {
    mm_stub_tool curl 'exit 1'
    run fetch_latest_version 3
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "fetch_latest_version: ignores a malformed VERSION value (not X.Y.Z)" {
    mm_stub_tool curl 'echo '"'"'VERSION="not-a-version"'"'"''
    run fetch_latest_version 3
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "fetch_latest_version: never lets a downstream SIGPIPE-style failure escape as an error" {
    # Simulates curl being killed mid-transfer. Must still return 0 with
    # empty output rather than aborting under set -e/pipefail.
    mm_stub_tool curl 'echo "VERSION=\"1.0.0\""; kill -PIPE $$ 2>/dev/null; true'
    run fetch_latest_version 3
    [ "${status}" -eq 0 ]
}
