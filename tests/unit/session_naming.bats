#!/usr/bin/env bats
# Pure-logic unit tests for the CWD-based session naming pipeline:
# truncate_component, substitute_special_chars, render_path_parts,
# format_session_name, canonical_path, session_name_for_path,
# validate_session_name, name_in_use, unique_session_name.

setup() {
    load '../helpers/common'
    mm_set_fake_home
    mm_source
}

# --- truncate_component ---

@test "truncate_component: shorter than max is unchanged" {
    result="$(truncate_component "abc" 20)"
    [ "${result}" = "abc" ]
}

@test "truncate_component: exactly at max is unchanged" {
    result="$(truncate_component "12345" 5)"
    [ "${result}" = "12345" ]
}

@test "truncate_component: one over max gets a mid-string ellipsis, total length == max" {
    # 6 chars, max 5: budget=4, left=ceil(4/2)=2, right=2
    result="$(truncate_component "abcdef" 5)"
    [ "${result}" = "ab…ef" ]
    [ "${#result}" -eq 5 ]
}

@test "truncate_component: odd budget splits with extra char on the left" {
    # 7 chars, max 5: budget=4, left=2, right=2 -> still 5 total (ellipsis counted in max)
    result="$(truncate_component "abcdefg" 5)"
    [ "${result}" = "ab…fg" ]
    [ "${#result}" -eq 5 ]
}

@test "truncate_component: max of 1 leaves no room for a right half" {
    result="$(truncate_component "abcdef" 1)"
    [ "${result}" = "…" ]
}

@test "truncate_component: max of 2 is left char + ellipsis, no right half" {
    result="$(truncate_component "abcdef" 2)"
    [ "${result}" = "a…" ]
    [ "${#result}" -eq 2 ]
}

@test "truncate_component: empty string is unchanged" {
    result="$(truncate_component "" 20)"
    [ "${result}" = "" ]
}

# --- substitute_special_chars ---

@test "substitute_special_chars: colon becomes underscore" {
    result="$(substitute_special_chars "foo:bar")"
    [ "${result}" = "foo_bar" ]
}

@test "substitute_special_chars: dot becomes underscore" {
    result="$(substitute_special_chars "foo.bar")"
    [ "${result}" = "foo_bar" ]
}

@test "substitute_special_chars: both colon and dot, multiple occurrences" {
    result="$(substitute_special_chars "a:b.c:d.e")"
    [ "${result}" = "a_b_c_d_e" ]
}

@test "substitute_special_chars: leaves ordinary text alone" {
    result="$(substitute_special_chars "hello-world_123")"
    [ "${result}" = "hello-world_123" ]
}

# --- format_session_name: home substitution ---

@test "format_session_name: exact home directory becomes '~/' (not bare '~')" {
    result="$(format_session_name "${HOME_REAL}" 20 60)"
    [ "${result}" = "~/" ]
}

@test "format_session_name: subdirectory of home becomes ~/sub" {
    result="$(format_session_name "${HOME_REAL}/sub" 20 60)"
    [ "${result}" = "~/sub" ]
}

@test "format_session_name: nested subdirectory of home" {
    result="$(format_session_name "${HOME_REAL}/a/b/c" 20 60)"
    [ "${result}" = "~/a/b/c" ]
}

@test "format_session_name: path outside home keeps a leading /" {
    result="$(format_session_name "/tmp/somewhere" 20 60)"
    [ "${result}" = "/tmp/somewhere" ]
}

@test "format_session_name: a path that merely starts with the same prefix as home, but isn't a subdirectory, is not treated as inside home" {
    # e.g. HOME=/Users/foo, path=/Users/foobar should NOT become ~bar.
    # HOME_REAL is overridden here to a short synthetic value so the
    # comparison itself is what's under test, independent of how long the
    # real sandbox $HOME happens to be (which would otherwise trigger
    # unrelated component-dropping and mask the actual check).
    HOME_REAL="/Users/foo"
    other="/Users/foobar"
    result="$(format_session_name "${other}" 20 60)"
    [ "${result}" = "${other}" ]
}

@test "format_session_name: root directory" {
    result="$(format_session_name "/" 20 60)"
    [ "${result}" = "/" ]
}

# --- format_session_name: per-component truncation ---

@test "format_session_name: a single overlong component gets truncated in place" {
    long="$(printf 'a%.0s' {1..30})" # 30 a's
    result="$(format_session_name "/${long}" 20 60)"
    [ "${#result}" -le 21 ] # leading / + 20-char component
    [[ "${result}" == *"…"* ]]
}

@test "format_session_name: colon/dot in a path component get substituted before truncation" {
    result="$(format_session_name "/tmp/foo:bar.baz" 20 60)"
    [ "${result}" = "/tmp/foo_bar_baz" ]
}

# --- format_session_name: whole-path dropping when still too long ---

@test "format_session_name: drops whole components from the left, with a single leading ellipsis, when still over the overall max" {
    path="/aaaaaaaaaa/bbbbbbbbbb/cccccccccc/dddddddddd/eeeeeeeeee"
    result="$(format_session_name "${path}" 20 20)"
    [ "${#result}" -le 20 ]
    [[ "${result}" == "…/"* ]]
    # the rightmost (most specific) component should be the one kept
    [[ "${result}" == *"eeeeeeeeee" ]]
}

@test "format_session_name: drops down to a single surviving component if needed" {
    path="/aaaaaaaaaa/bbbbbbbbbb/cccccccccc/verylongfinalcomponentnamehere"
    result="$(format_session_name "${path}" 20 22)"
    # only one component should survive, prefixed by the leading ellipsis
    [[ "${result}" == "…/"* ]]
    local rest="${result#…/}"
    [[ "${rest}" != *"/"* ]]
}

@test "format_session_name: never drops the last remaining component even if still too long" {
    # total_max impossibly small: per-component truncation still applies,
    # but once only one component is left, dropping stops (loop condition
    # requires more than one part left).
    result="$(format_session_name "/abcdefghijklmnopqrst" 20 5)"
    [ -n "${result}" ]
}

# --- canonical_path ---

@test "canonical_path: resolves an existing directory to its real absolute path" {
    d="$(mm_make_dir "${BATS_TEST_TMPDIR}/realdir")"
    result="$(canonical_path "${d}")"
    [ "${result}" = "$(cd "${d}" && pwd -P)" ]
}

@test "canonical_path: falls back to the input unchanged for a nonexistent path" {
    result="$(canonical_path "/no/such/path/at/all")"
    [ "${result}" = "/no/such/path/at/all" ]
}

@test "canonical_path: resolves a symlinked directory to its real target" {
    real="$(mm_make_dir "${BATS_TEST_TMPDIR}/real-target")"
    link="${BATS_TEST_TMPDIR}/link-to-target"
    ln -s "${real}" "${link}"
    result="$(canonical_path "${link}")"
    [ "${result}" = "$(cd "${real}" && pwd -P)" ]
}

# --- session_name_for_path (canonical_path + format_session_name together) ---

@test "session_name_for_path: end-to-end for a real subdirectory of home" {
    # session_name_for_path reads SESSION_NAME_COMPONENT_MAX/TOTAL_MAX as
    # globals normally set by load_config. Set them directly here since
    # this test only cares about the naming pipeline, not config loading
    # (that has its own dedicated tests).
    SESSION_NAME_COMPONENT_MAX=20
    SESSION_NAME_TOTAL_MAX=60
    mkdir -p "${HOME}/proj"
    result="$(session_name_for_path "${HOME}/proj")"
    [ "${result}" = "~/proj" ]
}

# --- validate_session_name ---

@test "validate_session_name: accepts an ordinary name" {
    run validate_session_name "my-session"
    [ "${status}" -eq 0 ]
}

@test "validate_session_name: rejects an empty name" {
    run validate_session_name ""
    [ "${status}" -ne 0 ]
}

@test "validate_session_name: rejects a name containing ':'" {
    run validate_session_name "foo:bar"
    [ "${status}" -ne 0 ]
}

@test "validate_session_name: rejects a name containing '.'" {
    run validate_session_name "foo.bar"
    [ "${status}" -ne 0 ]
}

@test "validate_session_name: rejects a name containing a newline" {
    run validate_session_name "$(printf 'foo\nbar')"
    [ "${status}" -ne 0 ]
}

# --- name_in_use / unique_session_name ---

@test "name_in_use: true when the name is in the list" {
    run name_in_use "b" "$(printf 'a\nb\nc')" ""
    [ "${status}" -eq 0 ]
}

@test "name_in_use: false when the name is not in the list" {
    run name_in_use "z" "$(printf 'a\nb\nc')" ""
    [ "${status}" -ne 0 ]
}

@test "name_in_use: excluded name never counts as in use (self-rename to same name)" {
    run name_in_use "a" "$(printf 'a\nb\nc')" "a"
    [ "${status}" -ne 0 ]
}

@test "name_in_use: a candidate containing '.' is matched literally, not as a regex wildcard" {
    # As a BRE, "a.b" would also match the literal string "aXb". Fixed-
    # string matching must not report a false collision here.
    run name_in_use "a.b" "$(printf 'aXb\nother')" ""
    [ "${status}" -ne 0 ]
}

@test "name_in_use: a candidate containing '.' still matches its own literal occurrence" {
    run name_in_use "a.b" "$(printf 'a.b\nother')" ""
    [ "${status}" -eq 0 ]
}

@test "unique_session_name: returns the candidate unchanged if free" {
    result="$(unique_session_name "abc" "$(printf 'xyz\nqrs')" "")"
    [ "${result}" = "abc" ]
}

@test "unique_session_name: appends -1 on a single collision" {
    result="$(unique_session_name "abc" "$(printf 'abc')" "")"
    [ "${result}" = "abc-1" ]
}

@test "unique_session_name: picks the lowest available suffix, reusing a freed gap" {
    # abc and abc-2 taken, abc-1 free: must reuse abc-1, not jump to abc-3
    result="$(unique_session_name "abc" "$(printf 'abc\nabc-2')" "")"
    [ "${result}" = "abc-1" ]
}

@test "unique_session_name: skips consecutively taken suffixes" {
    result="$(unique_session_name "abc" "$(printf 'abc\nabc-1\nabc-2')" "")"
    [ "${result}" = "abc-3" ]
}

@test "unique_session_name: a session renaming itself to its own current name is not a collision" {
    result="$(unique_session_name "abc" "$(printf 'abc\nother')" "abc")"
    [ "${result}" = "abc" ]
}

# --- shell_single_quote_escape ---

@test "shell_single_quote_escape: leaves an ordinary name unchanged" {
    result="$(shell_single_quote_escape "abc")"
    [ "${result}" = "abc" ]
}

@test "shell_single_quote_escape: escapes an embedded single quote so it round-trips through eval" {
    name="O'Brien"
    escaped="$(shell_single_quote_escape "${name}")"
    reconstructed="$(eval "printf '%s' '${escaped}'")"
    [ "${reconstructed}" = "${name}" ]
}

# --- create_unique_session ---

@test "create_unique_session: retries once instead of aborting when the first new-session attempt loses a race" {
    # Stub $TMI (normally "tmux -L socket") so the first invocation
    # (the initial 'new-session' attempt) fails, simulating a concurrent
    # multmux invocation having just claimed the name, and the second
    # (the retry) succeeds.
    local calls="${BATS_TEST_TMPDIR}/calls"
    echo 0 >"${calls}"
    local stub="${BATS_TEST_TMPDIR}/fake_tmi"
    cat >"${stub}" << STUB
#!/usr/bin/env bash
n=\$(( \$(cat "${calls}") + 1 ))
echo "\${n}" >"${calls}"
[[ "\${n}" -eq 1 ]] && exit 1
exit 0
STUB
    chmod +x "${stub}"
    TMI="${stub}"
    inner_session_list() { :; }
    run create_unique_session "abc" "/tmp"
    [ "${status}" -eq 0 ]
    [ "${output}" = "abc" ]
    [ "$(cat "${calls}")" -eq 2 ]
}

@test "create_unique_session: dies clearly if the retry also fails, instead of reporting bogus success" {
    # Both attempts fail (persistent failure, not just a one-off race).
    local stub="${BATS_TEST_TMPDIR}/fake_tmi_always_fails"
    printf '#!/usr/bin/env bash\nexit 1\n' >"${stub}"
    chmod +x "${stub}"
    TMI="${stub}"
    inner_session_list() { :; }
    run create_unique_session "abc" "/tmp"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"error:"* ]]
}
