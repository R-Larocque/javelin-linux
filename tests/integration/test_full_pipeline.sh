#!/usr/bin/env bash
# integration tests
# does not require root. validates build and symbol exports.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BUILD_DIR="${PROJECT_ROOT}/build"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

# test 1: library exports
test_dlopen_exports() {
    log_info "Test 1: Library exports..."
    local lib="${BUILD_DIR}/libjavelin.so"

    if [[ ! -f "$lib" ]]; then
        log_fail "libjavelin.so not found in ${BUILD_DIR}"
        return 1
    fi

    # Check the complete expected public dynamic-symbol API.
    local expected=(
        jv_init
        jv_fini
        jv_query_system_info
        jv_query_process_info
        jv_read_memory
        jv_write_memory
        jv_debug_attach
        jv_debug_detach
    )

    local missing=0
    local symbols
    symbols="$(nm -D --defined-only "$lib")"

    for sym in "${expected[@]}"; do
        if ! grep -Eq "[[:space:]]${sym}$" <<< "$symbols"; then
            log_fail "Missing dynamic export: $sym"
            missing=$((missing + 1))
        fi
    done

    if [[ $missing -ne 0 ]]; then
        log_fail "$missing/${#expected[@]} expected exports are missing"
        return 1
    fi

    log_pass "All ${#expected[@]} expected dynamic exports found"
}

# test 2: seccomp
test_seccomp_install() {
    log_info "Test 2: Seccomp filter installation..."

    # This integration test does not install or verify a seccomp filter.
    log_info "SKIP: seccomp behavior is covered separately by the unit test suite"
}

# test 3: proton spec (currently skipped)
test_proton_spec() {
    log_info "Test 3: Proton override spec JSON validity..."

    log_info "Proton integration spec removed (native Linux build, no Wine/Proton)"
    log_info "SKIP: no Wine/Proton integration test is implemented"
}

# test 4: eBPF syntax check
test_ebpf_syntax() {
    log_info "Test 4: eBPF source syntax check..."

    local src="${PROJECT_ROOT}/src/ebpf/javelin_monitor.bpf.c"
    local arch="$(uname -m)"
    local target_arch
    case "$arch" in
        x86_64)  target_arch="x86" ;;
        aarch64) target_arch="arm64" ;;
        *)       target_arch="x86" ;;
    esac

    local vmlinux="${BUILD_DIR}/vmlinux.h"

    if [[ ! -s "$vmlinux" ]]; then
        log_info "SKIP: ${vmlinux} is missing; run './scripts/setup_ebpf.sh build-ebpf' first"
        return 0
    fi

    if ! clang -target bpf \
        -D"__TARGET_ARCH_${target_arch}" \
        -I"${BUILD_DIR}" \
        -I"/usr/include/${arch}-linux-gnu" \
        -I/usr/include/bpf \
        -fsyntax-only "$src"; then
        log_fail "eBPF source has syntax errors"
        return 1
    fi

    log_pass "eBPF source syntax OK"
}

# test 5: unit tests
test_unit() {
    log_info "Test 5: Unit test suite..."

    local test_bin="${BUILD_DIR}/test_javelin"
    if [[ ! -f "$test_bin" ]]; then
        test_bin="${BUILD_DIR}/test_syscall_proxy"
    fi
    if [[ ! -f "$test_bin" ]]; then
        log_fail "Unit test binaries not built"
        return 1
    fi

    if ! "$test_bin"; then
        log_fail "$test_bin failed"
        return 1
    fi

    log_pass "All unit tests passed"
}


main() {
    echo "integration tests"
    echo ""

    local failed=0

    test_dlopen_exports   || failed=$((failed + 1))
    test_seccomp_install  || failed=$((failed + 1))
    test_proton_spec      || failed=$((failed + 1))
    test_ebpf_syntax      || failed=$((failed + 1))
    test_unit             || failed=$((failed + 1))

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}all passed${NC}"
        return 0
    else
        echo -e "${RED}$failed failed${NC}"
        return 1
    fi
}

main "$@"
