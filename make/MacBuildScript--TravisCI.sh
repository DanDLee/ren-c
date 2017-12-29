${TOOLS}gcc --version

if [[ \"$TRAVIS_OS_NAME\" == \"osx\" ]]; then export MAKE_JOBS=`sysctl -n hw.ncpu`; fi

TOP_DIR=${PWD}

if [[ ${OS_ID} = \"0.3.40\" || ${OS_ID} = \"0.3.1\" ]]; then
    # Use prebuilt binaries
    if [[ ${OS_ID} = \"0.3.40\" ]]; then
        export PKG_CONFIG_PATH=${TOP_DIR}/external/ffi-prebuilt/lib64/pkgconfig
    else
        export PKG_CONFIG_PATH=${TOP_DIR}/external/ffi-prebuilt/lib32/pkgconfig
    fi
    # --define-prefix would be better, but it is not recognized
    export PKGCONFIG=\"pkg-config --define-variable=prefix=${TOP_DIR}/external/ffi-prebuilt\"
    # check cflags and libs
    ${PKGCONFIG} --cflags libffi
    ${PKGCONFIG} --libs libffi
elif [[ -z ${FFI} || ${FFI} != \"no\" ]]; then
    # Build libffi
    mkdir build
    cd external/libffi
    ./autogen.sh
    cd ${TOP_DIR}/build
    if [[ -z ${HOST} ]]; then
        ${TOP_DIR}/external/libffi/configure --prefix=$PWD/fakeroot CFLAGS=${ARCH_CFLAGS}
    else #cross-compiling
        ${TOP_DIR}/external/libffi/configure --prefix=$PWD/fakeroot --host=${HOST}
    fi
    make -j ${MAKE_JOBS}
    make install
    export PKG_CONFIG_PATH=$PWD/fakeroot/lib/pkgconfig
    # check cflags and libs
    pkg-config --cflags libffi
    pkg-config --libs libffi

    ls `pkg-config --variable=toolexeclibdir libffi`
    #remove dynamic libraries to force it to link with static libraries
    rm -f `pkg-config --variable=toolexeclibdir libffi`/*.so*
    rm -f `pkg-config --variable=toolexeclibdir libffi`/*.dylib*
    rm -f `pkg-config --variable=toolexeclibdir libffi`/*.dll*
    ls `pkg-config --variable=toolexeclibdir libffi`
fi


cd ${TOP_DIR}/make/

if [[ ! -z ${TCC} ]]; then
    mkdir tcc
    cd tcc
    if [[ ${OS_ID} != \"0.4.40\" ]]; then
        #generate cross-compiler (on x86_64 host and target for i386)
        echo \"Generating the cross-compiler\"
        ${TOP_DIR}/external/tcc/configure --enable-cross --extra-cflags=\"-DEMBEDDED_IN_R3\"
        make -j ${MAKE_JOBS}
        mkdir bin
        cp *tcc bin #save cross-compilers
        ls bin/ #take a look at the cross-compilers
        make clean
        #generate libtcc.a
        # libtcc.a requires --enable-mingw32, or it doesn't think it's a native compiler and disables tcc_run
        echo \"Generating libtcc.a\"
        if [[ ${OS_ID} = \"0.4.4\" ]]; then
            ${TOP_DIR}/external/tcc/configure --cpu=x86 --extra-cflags=\"-DEMBEDDED_IN_R3 ${ARCH_CFLAGS}\"
        elif [[ ${OS_ID} == \"0.3.1\" ]]; then #x86-win32
            ${TOP_DIR}/external/tcc/configure --cpu=x86 --extra-cflags=\"-DEMBEDDED_IN_R3\" --enable-mingw32 --cross-prefix=${TOOLS}
        else #x86_64-win32
            ${TOP_DIR}/external/tcc/configure --enable-mingw32 --cpu=x86_64 --extra-cflags=\"-DEMBEDDED_IN_R3\" --cross-prefix=${TOOLS}
        fi
        make libtcc.a && cp libtcc.a libtcc.a.bak

        #generate libtcc1.a
        # --enable-mingw32 must be turned off, or it will try to compile with tcc.exe
        make clean

        echo \"Generating libtcc1.a\"
        if [[ ${OS_ID} = \"0.4.4\" ]]; then
            ${TOP_DIR}/external/tcc/configure --cpu=x86 --extra-cflags=\"-DEMBEDDED_IN_R3 ${ARCH_CFLAGS}\"
        elif [[ ${OS_ID} == \"0.3.1\" ]]; then #x86-win32
            ${TOP_DIR}/external/tcc/configure --cpu=x86 --extra-cflags=\"-DEMBEDDED_IN_R3\" --cross-prefix=${TOOLS}
        else #x86_64-win32
            ${TOP_DIR}/external/tcc/configure --cpu=x86_64 --extra-cflags=\"-DEMBEDDED_IN_R3\" --cross-prefix=${TOOLS}
        fi

        echo \"make libtcc1.a\"
        make libtcc1.a XCC=${TOOLS}gcc XAR=${TOOLS}ar || echo \"ignoring error in building libtcc1.a\" #this could fail to build tcc due to lack of '-ldl' on Windows
        cp bin/* . #restore cross-compilers, libtcc1.a depends on tcc
        touch tcc #update the timestamp so it won't be rebuilt
        echo \"ls\"
        ls #take a look at files under current directory
        echo \"make libtcc1.a\"
        make libtcc1.a XCC=${TOOLS}gcc XAR=${TOOLS}ar

        echo \"Looking for symbol r3_tcc_alloca\"
        if [[ ${OS_ID} == \"0.3.1\" ]]; then #x86-win32
          ${TOOLS}objdump -t lib/i386/alloca86.o |grep alloca
        elif [[ ${OS_ID} == \"0.3.40\" ]]; then
          ${TOOLS}objdump -t lib/x86_64/alloca86_64.o |grep alloca
        fi

        #restore libtcc.a
        # make libtcc1.a could have generated a new libtcc.a
        cp libtcc.a.bak libtcc.a
    else
        ${TOP_DIR}/external/tcc/configure --extra-cflags=\"-DEMBEDDED_IN_R3 ${ARCH_CFLAGS}\"
    fi
    make
    cd ${TOP_DIR}/make
fi


GIT_COMMIT=\"$(git show --format=\"%H\" --no-patch)\"

echo ${GIT_COMMIT}

GIT_COMMIT_SHORT=\"$(git show --format=\"%h\" --no-patch)\"

echo ${GIT_COMMIT_SHORT}

if [[ (\"${OS_ID}\" = \"0.4.40\" || \"${OS_ID}\" = \"0.2.40\") && \"${DEBUG}\" != \"none\" ]]; then
    #
    # If building twice, don't specify GIT_COMMIT for the first build.
    # This means there's a test of the build process when one is not
    # specified, in case something is broken about that.  (This is how
    # most people will build locally, so good to test it.)
    #
    # Also request address sanitizer to be used for the first build.  It
    # is very heavyweight and makes the executable *huge* and slow, so
    # we do not apply it to any of the binaries which are uploaded to s3
    # -- not even debug ones.
    #
    make -f makefile.boot NUM_JOBS=${MAKE_JOBS} REBOL_TOOL=${REBOL_TOOL} CONFIG=\"configs/${CONFIG}\" STANDARD=\"${STANDARD}\" OS_ID=\"${OS_ID}\" RIGOROUS=\"${RIGOROUS}\" DEBUG=sanitize OPTIMIZE=2 STATIC=no ODBC_REQUIRES_LTDL=${ODBC_REQUIRES_LTDL}

    mv r3 r3-make;
    make clean;
    export R3_ALWAYS_MALLOC=1
    export REBOL_TOOL=./r3-make
fi


if [[ -z ${TCC} ]]; then
    make -f makefile.boot NUM_JOBS=${MAKE_JOBS} REBOL_TOOL=${REBOL_TOOL} CONFIG=\"configs/${CONFIG}\" STANDARD=\"${STANDARD}\" OS_ID=\"${OS_ID}\" DEBUG=\"${DEBUG}\" GIT_COMMIT=\"${GIT_COMMIT}\" RIGOROUS=\"${RIGOROUS}\" STATIC=\"${STATIC}\" WITH_FFI=${FFI} WITH_TCC=\"no\" ODBC_REQUIRES_LTDL=${ODBC_REQUIRES_LTDL}
else
    make -f makefile.boot NUM_JOBS=${MAKE_JOBS} REBOL_TOOL=${REBOL_TOOL} CONFIG=\"configs/${CONFIG}\" STANDARD=\"${STANDARD}\" OS_ID=\"${OS_ID}\" DEBUG=\"${DEBUG}\" GIT_COMMIT=\"${GIT_COMMIT}\" RIGOROUS=\"${RIGOROUS}\" STATIC=\"${STATIC}\" WITH_FFI=${FFI} WITH_TCC=\"%${PWD}/tcc/${TCC}\" ODBC_REQUIRES_LTDL=${ODBC_REQUIRES_LTDL}
fi


if [[ \"${OS_ID}\" = \"0.4.40\" || \"${OS_ID}\" = \"0.4.4\" ]]; then
    ldd ./r3
elif [[ \"${OS_ID}\" = \"0.2.40\" ]]; then
    otool -L ./r3
fi


if [[ \"${OS_ID}\" = \"0.4.40\" || \"${OS_ID}\" = \"0.4.4\" || \"${OS_ID}\" = \"0.2.40\" ]]; then
    ./r3 --do \"print {Testing...} quit/with either find to-string read https://example.com {<h1>Example Domain</h1>} [0] [1]\";
    R3_EXIT_STATUS=$?;
else
    R3_EXIT_STATUS=0;
fi


echo ${R3_EXIT_STATUS}

if [[ \"${OS_ID}\" = \"0.4.40\" || \"${OS_ID}\" = \"0.4.4\" ]]; then
    ./r3 ../tests/misc/qsort_r.r
    R3_EXIT_STATUS=$?;
else
    R3_EXIT_STATUS=0;
fi


echo ${R3_EXIT_STATUS}

if [[ ! -z \"$TCC\" && \"$TCC\" != \"no\" && ( \"${OS_ID}\" = \"0.4.40\" || \"${OS_ID}\" = \"0.4.4\" ) ]]; then
    ./r3 ../tests/misc/fib.r
    R3_EXIT_STATUS=$?;
else
    R3_EXIT_STATUS=0;
fi


echo ${R3_EXIT_STATUS}

rm -rf objs

rm -f makefile*

rm -f Toolchain*

rm -f r3-make*

rm r3-linux-x64-gbf237fc-static

rm r3-osx-x64-gbf237fc

rm -f CMakeLists.txt

rm -rf tcc

NEW_NAME=${OS_ID}/r3-${GIT_COMMIT_SHORT}

if [[ \"${DEBUG}\" != \"none\" ]]; then NEW_NAME+=\"-debug\"; fi

if [[ \"${STANDARD}\" = \"c++\" || \"${STANDARD}\" = \"c++0x\" || \"${STANDARD}\" = \"c++11\" || \"${STANDARD}\" = \"c++14\" || \"${STANDARD}\" = \"c++17\" ]]; then
    NEW_NAME+=\"-cpp\";
fi


echo ${NEW_NAME}

mkdir ${OS_ID}

if [[ -e \"r3.exe\" ]]; then
     mv r3.exe ${NEW_NAME}.exe;
else
     mv r3 ${NEW_NAME};
fi


(exit ${R3_EXIT_STATUS})
