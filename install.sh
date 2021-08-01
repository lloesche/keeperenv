#!/usr/bin/env bash
set -e
set -x
num_cc=32
ZLIB_VERSION="1.2.11"
OPENSSL_VERSION="1.1.1k"
PYTHON_VERSION="3.9.6"
ARANGODB_VERSION="3.7.13"
BZIP2_VERSION="1.0.8"
SQLITE_VERSION="3360000"
prefix_dir="$HOME/builder"
build_dir="$prefix_dir/src"
install_dir="$prefix_dir/dist"
download_dir="$prefix_dir/dl"
zlib_download_url="https://zlib.net/zlib-${ZLIB_VERSION}.tar.xz"
openssl_download_url="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
python_download_url="https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz"
arangodb_download_url="https://download.arangodb.com/Source/ArangoDB-${ARANGODB_VERSION}.tar.bz2"
bzip2_git_repo="git://sourceware.org/git/bzip2.git"
sqlite_download_url="https://www.sqlite.org/2021/sqlite-autoconf-${SQLITE_VERSION}.tar.gz"
arangodb_zip_download_url="https://github.com/arangodb/arangodb/archive/refs/heads/devel.zip"
arangodb_download_url_macos="https://download.arangodb.com/arangodb37/Community/MacOSX/arangodb3-macos-${ARANGODB_VERSION}.tar.gz"
arangodb_download_url_linux="https://download.arangodb.com/arangodb37/Community/Linux/arangodb3-linux-${ARANGODB_VERSION}.tar.gz"
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
    make_bzip2
    make_openssl
    make_sqlite
    make_python
    make_arangodb
    cleanup
}

make sqlite() {
    local dl_to="$download_dir/sqlite.tar.gz"
    local build_in="$build_dir/sqlite"

    log "Building sqlite"
    mkdir -p "$build_in"
    debug "Downloading $sqlite_download_url to $dl_to"
    curl -L -C - -o "$dl_to" "$sqlite_download_url"
    tar xzvf "$dl_to" --strip-components=1 -C "$build_in"
    cd "$build_in"
    
    ./configure \
        --prefix="$install_dir"
    make -j $num_cc
}

make bzip2() {
    local repo="$build_dir/bzip2"

    log "Building bzip2"
    cd "$build_dir"
    git clone "$bzip2_git_repo"
    git checkout "bzip2-$BZIP2_VERSION"
    make install PREFIX="$install_dir"
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
    make -j $num_cc
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
        -O2 -DFORTIFY_SOURCE=2
    make depend
    make -j $num_cc
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
    make -j $num_cc
    make install
}

make_arangodb() {
    local dl_to="$download_dir/arangodb.zip"
    local build_in="$build_dir/arangodb-devel"
    local cmake_args=()
    local build_prefix=()

    log "Building ArangoDB"
    mkdir -p "$build_in"
    arangodb_download_url=$arangodb_zip_download_url
    debug "Downloading $arangodb_download_url to $dl_to"
#    curl -L -C - -o "$dl_to" "$arangodb_download_url"
#    tar xjvf "$dl_to" --strip-components=1 -C "$build_in"
    cd "$build_dir"
    unzip "$dl_to"
    cd "$build_in"
    case "$sysname" in
    Darwin)
        cmake_args=(-DCMAKE_OSX_DEPLOYMENT_TARGET=10.11)
        if [ "$archname" = "arm64" ]; then
            build_prefix=(arch -x86_64)
        fi
        ;;
    esac

    mkdir build
    cd build
    "${build_prefix[@]}" cmake .. \
        -DOPENSSL_ROOT_DIR="$install_dir" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" \
        "${cmake_args[@]}"
    "${build_prefix[@]}" make -j $num_cc
}

install_arangodb() {
    local dl_to="$download_dir/arangodb.tar.gz"
    local build_in="$build_dir/arangodb"
    local download_url

    log "Installing ArangoDB"
    mkdir -p "$build_in"
    case "$sysname" in
    Darwin)
        download_url="$arangodb_download_url_macos"
        ;;
    Linux)
        download_url="$arangodb_download_url_linux"
        ;;
    esac


    debug "Downloading $download_url to $dl_to"
    curl -L -C - -o "$dl_to" "$download_url"
    tar xzvf "$dl_to" --strip-components=1 -C "$build_in"
    cd "$build_in"
    rm -f README
    cp -a * "$install_dir"
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
