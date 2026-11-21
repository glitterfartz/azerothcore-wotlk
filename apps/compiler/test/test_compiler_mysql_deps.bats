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
