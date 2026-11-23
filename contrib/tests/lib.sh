# shellcheck shell=bash
#
# Sourced by the tests in this directory: reports every check, and `finish`
# fails the test if one of them did.

failures=0

ok() {
    echo "ok - $*"
}

not_ok() {
    echo "not ok - $*"
    failures=$((failures + 1))
}

# check <description> <command...>: the command has to succeed.
check() {
    local description="$1"
    shift
    if "$@"; then ok "$description"; else not_ok "$description"; fi
}

# check_not <description> <command...>: the command has to fail.
check_not() {
    local description="$1"
    shift
    if "$@"; then not_ok "$description"; else ok "$description"; fi
}

finish() {
    if ((failures > 0)); then
        echo "$failures check(s) failed" >&2
        exit 1
    fi
}
