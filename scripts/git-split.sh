#!/usr/bin/env bash

TEMP=$(getopt -o hvdymr: --long help,verbose,debug,submodule,remote:,visibility: \
    -n 'javawrap' -- "$@")

if [ $? != 0 ]; then
    echo "Terminating..." >&2
    exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Must be run inside a git repository" >&2
    exit 1
fi

eval set -- "$TEMP"

SCRIPT="$(basename $0)"

read -r -d '' USAGE <<-EOF
USAGE: $SCRIPT [OPTIONS]

OPTIONS:
    -h, --help                          Show this message
    -v, --verbose                       Show more output
    -d, --debug                         NOT IMPLEMENTED
    -y, --confirm                       Do not prompt for confirmation
    -m, --submodule                     
            Migrate directory in original repository to submodule

    -r, --remote=<user/repo>         
            Github remote, defaults to $(git config user.username)/${directory}

        --private                       
            Create the new remote repository as private. It is created 
            as public if ommited

ARGS:
    <DIRECTORY>...  Directory to split out of original repository, 
                    defaults to current directory
EOF

VERBOSE=false
DEBUG=false
CONFIRMED=false
SUBMODULE=false
REPO=$(git rev-parse --show-toplevel)
DIRECTORY="$(basename $(git rev-parse --show-prefix))"
REMOTE="$(basename $DIRECTORY)/$(git config user.username)"
VISIBILITY="--public"

while true; do
    case "$1" in
    -h | --help)
        echo "$USAGE"
        exit 0
        ;;
    -v | --verbose)
        VERBOSE=true
        shift
        ;;
    -d | --debug)
        DEBUG=true
        shift
        ;;
    -y)
        CONFIRMED=true
        shift
        ;;
    -m | --submodule)
        SUBMODULE=true
        shift
        ;;
    -r | --remote)
        REMOTE="$2"
        shift 2
        ;;
    --public | --private)
        VISIBILITY="$1"
        shift
        ;;
    --)
        shift
        break
        ;;
    *)
        DIRECTORY="$2"
        shift
        break
        ;;
    esac
done

if [[ "$REMOTE" = "$(basename $DIRECTORY)/$(git config user.username)" && $? -ne 0 ]]; then
    echo "ERROR: No remote provided and user.username was not set." >&2
    echo "$USAGE"
    exit 1
fi

cd $REPO

git subtree split -P $DIRECTORY -b $DIRECTORY

cd "$(mktemp -d)"

git init && git pull $REPO $DIRECTORY && git branch -M main

files=(".gitignore" ".gitattributes" ".vscode" "LICENSE")
for f in "${files[@]}"; do
    if [ ! -e "./${f}" && -e "${REPO}/${f}" ]; then
        printf '%s\n' "Copying ${f} to new repository..."
        cp -r "${REPO}/${f}" ./
    fi
done

git add -A && git commit -m "split out $DIRECTORY into submodule"

# TODO check if remote already exists
if command -v gh &>/dev/null; then
    yes "n" | gh repo create --confirm "${REMOTE}" "${VISIBILITY}"
else
    printf '%s\n' 'gh cli tool could not be found. Explicitly adding git remote to your local repository.'
    git remote add origin https://github.com/${REMOTE}
fi

if git ls-remote git@github.com:${REMOTE} &>/dev/null; then
    git push -u origin main
else
    printf '%s\n' 'Remote repository not found.'
fi

if [ $? -ne 0 ]; then
    printf '\n%s\n' 'Verify/create the remote repository and push to it with the following command: '
    printf '\n\t%s%s%s\n\n' '`cd ' "$(pwd)" ' && git push -u origin main`'

    printf '\t%s\n' \
        '*********************************************************************************' \
        '* The new repository was created in a temp directory!                           *' \
        '* If the local repository is not pushed to remote, it will be lost on reboot.   *' \
        '*********************************************************************************'
else
    tempdir="$(pwd)"
    cd "$REPO"
    rm -rf "$tempdir"
fi

# Migrate to submodule

if [ "$SUBMODULE" != true ]; then
    exit 0
fi

# TODO fix and remove warning

printf 'Migrating the original subdirectory to submodule.\n'

if [ "$QUIET" != true ]; then
    printf '\t%s\n' \
        '*************************************************************************************' \
        '*  THIS IS NOT TESTED AND HAS A POSSIBLY OF DATA LOSS!                              *' \
        '*                                                                                   *' \
        '*  This runs `git rm -rf` and `rm -rf` on the original subdirectory.                *' \
        '*  Double check you succesfully migrated the subdirectory to the new repository.    *' \
        '*************************************************************************************'
fi

if [ "$CONFIRMED" != true ]; then
    read -p "Proceed? (Y/n) " -n 1 -r
    printf '\n'
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CONFIRMED=true
    else
        [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
    fi
fi

cd $REPO

git rm -rf $DIRECTORY
rm -rf $DIRECTORY

git submodule add git@github.com:$REMOTE $DIRECTORY
git submodule update --init --recursive

git commit -m "split out $DIRECTORY into submodule"

if [ $? -ne 0 ]; then
    printf '%s\n' 'Submodule succesfully added. Be sure to `git push -u origin main` after verifing the migration.'
fi
