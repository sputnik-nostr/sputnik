# shellcheck shell=bash
#
# Sourced by tests that need AppDirs: tiny ELF files with the NEEDED and
# RUNPATH entries a test asks for. Needs a C compiler and patchelf.

# elf_init <dir>: builds the executable and the shared library to copy from.
elf_init() {
    elf_dir="$1"
    printf 'int main(void) { return 0; }\n' >"$elf_dir/exe.c"
    printf 'int answer(void) { return 42; }\n' >"$elf_dir/lib.c"
    "${CC:-cc}" -o "$elf_dir/exe" "$elf_dir/exe.c"
    "${CC:-cc}" -shared -fPIC -o "$elf_dir/lib.so" "$elf_dir/lib.c"
}

# elf_exe <path> <runpath> [needed...]
elf_exe() {
    local path="$1" runpath="$2" needed
    shift 2
    cp "$elf_dir/exe" "$path"
    patchelf --set-rpath "$runpath" "$path"
    for needed in "$@"; do
        patchelf --add-needed "$needed" "$path"
    done
}

# elf_lib <path> <soname> <runpath> [needed...]
elf_lib() {
    local path="$1" soname="$2" runpath="$3" needed
    shift 3
    cp "$elf_dir/lib.so" "$path"
    patchelf --set-soname "$soname" "$path"
    patchelf --set-rpath "$runpath" "$path"
    for needed in "$@"; do
        patchelf --add-needed "$needed" "$path"
    done
}
