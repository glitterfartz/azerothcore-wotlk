#!/usr/bin/env bats

# AzerothCore compiler: MySQL client download tests

if type -t bats_require_minimum_version >/dev/null 2>&1; then
  bats_require_minimum_version 1.5.0
fi

load '../../test-framework/bats_libs/acore-support'
load '../../test-framework/bats_libs/acore-assert'

setup() {
    compiler_setup
    export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export AC_BASH_LIB_PATH="$SCRIPT_DIR/../../deps/acore/bash-lib/src"
    export AC_MYSQL_DEP_DIR="$TEST_DIR/mysql-dep"
    export BINPATH="$TEST_DIR"
}

teardown() {
    acore_test_teardown
}

make_fake_sdk() {
    mkdir -p "$AC_MYSQL_DEP_DIR/include/mysql" "$AC_MYSQL_DEP_DIR/lib/private"
    touch "$AC_MYSQL_DEP_DIR/include/mysql.h"
    touch "$AC_MYSQL_DEP_DIR/lib/libmysqlclient.so"
    touch "$AC_MYSQL_DEP_DIR/lib/libmysqlclient.so.21"
    touch "$AC_MYSQL_DEP_DIR/lib/private/libssl.so.3"
}

@test "mysql-deps: comp_mysqlDepsDir respects AC_MYSQL_DEP_DIR" {
    run bash -c "
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDepsDir
    "
    [ "$status" -eq 0 ]
    [ "$output" = "$AC_MYSQL_DEP_DIR" ]
}

@test "mysql-deps: comp_mysqlDepsAvailable is false without the SDK" {
    run bash -c "
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDepsAvailable
    "
    [ "$status" -eq 1 ]
}

@test "mysql-deps: comp_mysqlDepsAvailable is true with headers and library" {
    make_fake_sdk
    run bash -c "
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDepsAvailable
    "
    [ "$status" -eq 0 ]
}

@test "mysql-deps: runtime copy installs shared library and private libs" {
    make_fake_sdk
    run bash -c "
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDepsInstallRuntime
    "
    [ "$status" -eq 0 ]
    [ -f "$BINPATH/lib/libmysqlclient.so.21" ]
    [ -f "$BINPATH/lib/private/libssl.so.3" ]
}

@test "mysql-deps: runtime copy is a no-op without the SDK" {
    run bash -c "
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDepsInstallRuntime
    "
    [ "$status" -eq 0 ]
    [ ! -d "$BINPATH/lib" ]
}

make_tarball_fixture() {
    local top="$TEST_DIR/mysql-8.0.46-linux-glibc2.17-x86_64-minimal"
    mkdir -p "$top/include/mysql" "$top/lib/private"
    touch "$top/include/mysql.h"
    touch "$top/lib/libmysqlclient.so" "$top/lib/libmysqlclient.so.21"
    touch "$top/lib/private/libssl.so.3"
    tar -cJf "$TEST_DIR/fixture.tar.xz" -C "$TEST_DIR" "$(basename "$top")"
    sha256sum "$TEST_DIR/fixture.tar.xz" | cut -d' ' -f1 > "$TEST_DIR/fixture.sha"
    rm -rf "$top"
}

# Mock curl: copies the fixture to the -o target; records invocation.
make_curl_mock() {
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
echo called >> "$CURL_CALL_LOG"
cp "$CURL_FIXTURE" "$out"
EOF
    chmod +x "$TEST_DIR/bin/curl"
    export CURL_CALL_LOG="$TEST_DIR/curl.calls"
    export CURL_FIXTURE="$TEST_DIR/fixture.tar.xz"
}

@test "mysql-deps: rejects unsupported architectures" {
    run bash -c "
        export AC_MYSQL_DEP_ARCH=riscv64
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDeps
    "
    [ "$status" -eq 1 ]
    [[ "$output" =~ "only available for x86_64" ]]
}

@test "mysql-deps: skips download when marker and files match" {
    make_fake_sdk
    printf '8.0.46 deadbeef\n' > "$AC_MYSQL_DEP_DIR/.installed"
    make_curl_mock
    run bash -c "
        export AC_MYSQL_DEP_SHA256=deadbeef
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDeps
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ "already installed" ]]
    [ ! -f "$CURL_CALL_LOG" ]
}

@test "mysql-deps: downloads, verifies and extracts the SDK" {
    make_tarball_fixture
    make_curl_mock
    run bash -c "
        export AC_MYSQL_DEP_SHA256=\$(cat '$TEST_DIR/fixture.sha')
        export AC_MYSQL_DEP_URL=http://example.invalid/mysql.tar.xz
        export AC_MYSQL_DEP_ARCH=x86_64
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDeps
    "
    [ "$status" -eq 0 ]
    [ -f "$AC_MYSQL_DEP_DIR/include/mysql.h" ]
    [ -f "$AC_MYSQL_DEP_DIR/lib/libmysqlclient.so.21" ]
    [ -f "$AC_MYSQL_DEP_DIR/lib/private/libssl.so.3" ]
    [ "$(cat "$AC_MYSQL_DEP_DIR/.installed")" = "8.0.46 $(cat "$TEST_DIR/fixture.sha")" ]
}

@test "mysql-deps: rejects checksum mismatch and leaves no SDK" {
    make_tarball_fixture
    make_curl_mock
    run bash -c "
        export AC_MYSQL_DEP_SHA256=0000000000000000000000000000000000000000000000000000000000000000
        export AC_MYSQL_DEP_URL=http://example.invalid/mysql.tar.xz
        export AC_MYSQL_DEP_ARCH=x86_64
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDeps
    "
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Checksum verification failed" ]]
    [ ! -f "$AC_MYSQL_DEP_DIR/include/mysql.h" ]
    [ ! -f "$AC_MYSQL_DEP_DIR/.installed" ]
}

@test "mysql-deps: fails cleanly when download fails" {
    cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/usr/bin/env bash
exit 22
EOF
    chmod +x "$TEST_DIR/bin/curl"
    run bash -c "
        export AC_MYSQL_DEP_ARCH=x86_64
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDeps
    "
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Download failed" ]]
    [ ! -d "$AC_MYSQL_DEP_DIR/include" ]
}

@test "mysql-deps: re-extracts when the marker version is stale" {
    make_tarball_fixture
    make_curl_mock
    mkdir -p "$AC_MYSQL_DEP_DIR/include"
    touch "$AC_MYSQL_DEP_DIR/include/stale.h"
    printf '8.0.1 oldsha\n' > "$AC_MYSQL_DEP_DIR/.installed"
    run bash -c "
        export AC_MYSQL_DEP_VERSION=8.0.46
        export AC_MYSQL_DEP_SHA256=\$(cat '$TEST_DIR/fixture.sha')
        export AC_MYSQL_DEP_URL=http://example.invalid/mysql.tar.xz
        export AC_MYSQL_DEP_ARCH=x86_64
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDeps
    "
    [ "$status" -eq 0 ]
    [ ! -f "$AC_MYSQL_DEP_DIR/include/stale.h" ]
    [ -f "$AC_MYSQL_DEP_DIR/include/mysql.h" ]
}

@test "mysql-deps: warns but proceeds when SHA is empty" {
    make_tarball_fixture
    make_curl_mock
    run bash -c "
        export AC_MYSQL_DEP_SHA256=
        export AC_MYSQL_DEP_URL=http://example.invalid/mysql.tar.xz
        export AC_MYSQL_DEP_ARCH=x86_64
        source '$SCRIPT_DIR/includes/functions.sh'
        comp_mysqlDeps
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ "skipping checksum verification" ]]
    [ -f "$AC_MYSQL_DEP_DIR/include/mysql.h" ]
}

make_cmake_mock() {
    cat > "$TEST_DIR/bin/cmake" << 'EOF'
#!/usr/bin/env bash
echo "cmake-args:$*"
EOF
    chmod +x "$TEST_DIR/bin/cmake"
}

run_comp_configure() {
    run bash -c "
        export BUILDPATH='$TEST_DIR/build'
        export BINPATH='$TEST_DIR'
        export AC_CCACHE=false
        source '$SCRIPT_DIR/includes/functions.sh'
        runHooks() { :; }
        comp_configure
    "
}

@test "configure: passes downloaded MySQL paths to cmake" {
    make_fake_sdk
    make_cmake_mock
    run_comp_configure
    [ "$status" -eq 0 ]
    [[ "$output" =~ "-DMYSQL_INCLUDE_DIR=$AC_MYSQL_DEP_DIR/include" ]]
    [[ "$output" =~ "-DMYSQL_LIBRARY=$AC_MYSQL_DEP_DIR/lib/libmysqlclient.so" ]]
    [ -f "$BINPATH/lib/libmysqlclient.so.21" ]
}

@test "configure: leaves MySQL detection untouched without the SDK" {
    make_cmake_mock
    run_comp_configure
    [ "$status" -eq 0 ]
    [[ "$output" != *"-DMYSQL_LIBRARY=$AC_MYSQL_DEP_DIR"* ]]
}

