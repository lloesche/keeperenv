#!/usr/bin/env bash
set -e
set -x
ZLIB_VERSION="1.2.11"
OPENSSL_VERSION="1.1.1k"
PYTHON_VERSION="3.9.6"
ARANGODB_VERSION="3.7.13"
prefix_dir="$HOME/builder"
build_dir="$prefix_dir/src"
install_dir="$prefix_dir/dist"
download_dir="$prefix_dir/dl"
zlib_download_url="https://zlib.net/zlib-${ZLIB_VERSION}.tar.xz"
openssl_download_url="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
python_download_url="https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz"
arangodb_download_url="https://download.arangodb.com/Source/ArangoDB-${ARANGODB_VERSION}.tar.bz2"
sysname=$(uname -s)
archname=$(uname -m)

main() {
    export PATH="$install_dir/bin:$PATH"
    export CFLAGS="-I$install_dir/include"
    export CPPFLAGS="-I$install_dir/include"
    export LDFLAGS="-L$install_dir/lib"
    case "$sysname" in
    Linux)
        export LD_LIBRARY_PATH="$install_dir/lib"
        ;;
    Darwin)
        export MACOSX_DEPLOYMENT_TARGET=10.13
        export DYLD_FALLBACK_LIBRARY_PATH="$install_dir/lib"
        ;;
    *)
        error "Unable to build OpenSSL for $sysname ($archname)"
        exit 1
        ;;
    esac

    rm -rf "$build_dir" "$install_dir"
    mkdir -p "$download_dir" "$build_dir" "$install_dir"
    cd "$prefix_dir"

    make_zlib
    make_openssl
    make_python
    make_arangodb
    cleanup
}


make_zlib() {
    local dl_to="$download_dir/zlib.tar.xz"
    local build_in="$build_dir/zlib"

    log "Building zlib"
    mkdir -p "$build_in"
    debug "Downloading $zlib_download_url to $dl_to"
    curl -L -C - -o "$dl_to" "$zlib_download_url"
    tar xvf "$dl_to" --strip-components=1 -C "$build_in"
    cd "$build_in"

    ./configure \
        --prefix="$install_dir"
    make test
    make install
}

make_openssl() {
    local dl_to="$download_dir/openssl.tar.gz"
    local build_in="$build_dir/openssl"

    log "Building OpenSSL"
    mkdir -p "$build_in"
    debug "Downloading $openssl_download_url to $dl_to"
    curl -L -C - -o "$dl_to" "$openssl_download_url"
    tar xzvf "$dl_to" --strip-components=1 -C "$build_in"

    case "$sysname" in
    Linux)
        build_openssl_platform linux x86_64 true
        ;;
    Darwin)
        build_openssl_platform darwin64 x86_64-cc false
        build_openssl_platform darwin64 arm64-cc false
        merge_openssl_universal2
        ;;
    esac
}

build_openssl_platform() {
    local platform=$1
    local arch=$2
    local make_install=$3
    local copy_from="$build_dir/openssl"
    local build_in="$build_dir/openssl-${arch}"

    cp -a "$copy_from" "$build_in"
    cd "$build_in"
    ./Configure \
        --prefix="$install_dir" \
        --openssldir="$install_dir/etc/ssl" \
        "${platform}-${arch}" \
        shared \
        enable-ec_nistp_64_gcc_128 \
        no-rc4 \
        no-ssl3 \
        no-comp \
        -Wa,--noexecstack -O2 -DFORTIFY_SOURCE=2
    make depend
    make
    if [ $make_install = true ]; then
        make install
    fi
}

merge_openssl_universal2() {
    cd "$build_dir"
    replace=(apps/openssl libssl.1.1.dylib libcrypto.1.1.dylib engines/ossltest.dylib engines/padlock.dylib engines/dasync.dylib engines/capi.dylib)
    cp -a "$build_dir/openssl-arm64-cc" "$build_dir/openssl-mac"
    cd "$build_dir/openssl-mac"
    for binlib in $replace;
    do
        rm -f "$build_dir/openssl-mac/$binlib"
        lipo -create "$build_dir/openssl-arm64-cc/$binlib" "$build_dir/openssl-x86_64-cc/$binlib" -output "$build_dir/openssl-mac/$binlib"
    done
    make install
}

make_python() {
    local dl_to="$download_dir/python.tar.xz"
    local build_in="$build_dir/python"
    local configure_args=()

    log "Building Python"
    mkdir -p "$build_in"
    debug "Downloading $python_download_url to $dl_to"
    curl -L -C - -o "$dl_to" "$python_download_url"
    tar xvf "$dl_to" --strip-components=1 -C "$build_in"
    cd "$build_in"

    case "$sysname" in
    Darwin)
        configure_args=(--enable-universalsdk --with-universal-archs=universal2)
        ;;
    esac

    ./configure \
        --prefix="$install_dir" \
        --enable-optimizations \
        --with-openssl="$install_dir" \
        "${configure_args[@]}"
    make
    make install
}

make_arangodb() {
    local dl_to="$download_dir/arangodb.tar.bz2"
    local build_in="$build_dir/arangodb"
    local cmake_args=()

    log "Building ArangoDB"
    mkdir -p "$build_in"
    debug "Downloading $arangodb_download_url to $dl_to"
    curl -L -C - -o "$dl_to" "$arangodb_download_url"
    tar xjvf "$dl_to" --strip-components=1 -C "$build_in"
    cd "$build_in"
    case "$sysname" in
    Darwin)
        cmake_args=(-DCMAKE_OSX_DEPLOYMENT_TARGET=10.11)
        ;;
    esac

    mkdir build
    cd build
    cmake .. \
        -DOPENSSL_ROOT_DIR=$install_dir \
        "${cmake_args[@]}"
}

cleanup() {
    log "Cleaning up"
    #rm -rf "$install_dir/share/"
}

log() {
    echo $*
}

debug() {
    log $*
}

main