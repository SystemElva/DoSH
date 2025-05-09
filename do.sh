#!/bin/sh

cd $(dirname $0)
HERE=$(pwd)



INI_FILE="/dev/stdin"
OUTPUT="/dev/stdout"
ACTION="UNKNOWN"

parse_query() {
    QUERY_ARGUMENT=$1

    LEN_QUERY=${#QUERY_ARGUMENT}
    CHAR_INDEX=0
    while [[ $CHAR_INDEX -le $LEN_QUERY ]];
    do
        if [[ ${QUERY_ARGUMENT:$CHAR_INDEX:1} == ':' ]];
        then
            SECTION_NAME=$(echo $QUERY_ARGUMENT | cut -c -$CHAR_INDEX)
            ((CHAR_INDEX+=2))
            KEY_NAME=$(echo $QUERY_ARGUMENT | cut -c $CHAR_INDEX-)
            return
        fi
        ((CHAR_INDEX+=1))
    done

}

parse_arguments() {
    ARGUMENT_INDEX=0
    ACCEPT="ALL"
    if [[ $ACTION == "GET-VALUE" ]];
    then
        ACCEPT="QUERY"
    fi

    if [[ $ACTION == "LIST-FIELDS" ]];
    then
        ACCEPT="SECTION-NAME"
    fi

    for ARGUMENT in "$@"
    do
        ((ARGUMENT_INDEX++))
        # Jump over the first two arguments as they're:
        #  1) the script's name
        #  2) the name of the action
        if [[ $ARGUMENT_INDEX < 2 ]];
        then
            continue
        fi
        case $ACCEPT in
            "ALL")
                case $ARGUMENT in
                    "-o" | "--output")
                        ACCEPT="OUTPUT"
                        ;;
                    "-q" | "--query")
                        ACCEPT="QUERY"
                        ;;
                esac
                # If the argument doesn't start with a minus,
                #  treat it as the input file's name.
                if [[ ${ARGUMENT:0:1} != "-" ]];
                then
                    INI_FILE=$ARGUMENT
                fi
                ;;
            "OUTPUT")
                if [[ ${ARGUMENT:0:1} == "-" ]];
                then
                    echo "Output file name cannot begin with '-'."
                    SUCCESS=0
                fi
                OUTPUT=$ARGUMENT
                ACCEPT="ALL"
                ;;
            "QUERY")
                parse_query $ARGUMENT
                ACCEPT="ALL"
                ;;
            "SECTION-NAME")
                SECTION_NAME=$ARGUMENT
                ACCEPT=ALL
                ;;
        esac
    done

    case $ACCEPT in
    "INI-FILE")
        echo "Missing input path at end of argument stream."
        exit -1
        ;;

    "OUTPUT")
        echo "Missing output path at end of argument stream."
        exit -2
        ;;
    esac
}

list_sections() {
    parse_arguments "$@"

    while read LINE
    do
        if [[ ${LINE:0:1} == "[" ]];
        then
            ((LAST_USED_OFFSET=${#LINE}-2))
            echo "${LINE:1:LAST_USED_OFFSET}" >> $OUTPUT
        fi
    done <$INI_FILE
}

list_fields() {
    parse_arguments "$@"

    SEARCHING=1
    while read LINE
    do
        # If the line is empty, it makes no sense to waste time on it.
        if [[ $LINE == "" ]];
        then
            continue
        fi

        # Check if the first character of this line is a number sign
        # And skip this line if it is, because that means it's a comment.
        if [[ ${LINE:0:1} == "#" ]];
        then
            continue
        fi
        if [[ $SEARCHING == 1 ]];
        then
            if [[ ${LINE:0:1} == "[" ]];
            then
                ((LAST_USED_OFFSET=${#LINE}-2))
                THIS_SECTION_NAME=${LINE:1:$LAST_USED_OFFSET}
                if [[ $THIS_SECTION_NAME == $SECTION_NAME ]];
                then
                    SEARCHING=0
                fi
                continue
            fi
        fi
        if [[ $SEARCHING == 0 ]];
        then
            if [[ ${LINE:0:1} == "[" ]];
            then
                return
            fi
            echo $LINE | cut -d= -f1 - >> $OUTPUT
        fi
    done <$INI_FILE
}

get_value() {
    parse_arguments "$@"

    SEARCHING=1
    while read LINE
    do
        # If the line is empty, it makes no sense to waste time on it.
        if [[ $LINE == "" ]];
        then
            continue
        fi

        # Check if the first character of this line is a number isgn
        # And skip this line if it is, because that means it's a comment.
        if [[ ${LINE:0:1} == "#" ]];
        then
            continue
        fi
        if [[ $SEARCHING == 1 ]];
        then
            if [[ ${LINE:0:1} == "[" ]];
            then
                ((LEN_LINE=${#LINE}-2))
                THIS_SECTION_NAME=${LINE:1:$LEN_LINE}
                if [[ $THIS_SECTION_NAME == $SECTION_NAME ]];
                then
                    SEARCHING=0
                fi
                continue
            fi
        fi
        if [[ $SEARCHING == 0 ]];
        then
            if [[ ${LINE:0:1} == "[" ]];
            then
                return
            fi
            CURRENT_KEY_NAME=$(echo $LINE | cut -d= -f1 -)

            # Cut away the possible spaces between
            # the key and the equals sign.
            CURRENT_KEY_NAME=$(echo $CURRENT_KEY_NAME | cut -d' ' -f1- -)

            if [[ $CURRENT_KEY_NAME == $KEY_NAME ]];
            then
                RAW_FIELD=$(echo $LINE | cut -d' ' -f3- -)

                # Remove the quotation marks in front of and after the field
                FIRST_CHARACTER=${RAW_FIELD:0:1}
                LAST_CHARACTER=${RAW_FIELD:((${#RAW_FIELD}-1)):1}
                if [[ $FIRST_CHARACTER == "\"" ]];
                then
                    if [[ $LAST_CHARACTER == "\"" ]];
                    then
                        ((LAST_WANTED_CHAR=${#RAW_FIELD}-1))
                        RAW_FIELD=$(echo $RAW_FIELD | cut -c 2-$LAST_WANTED_CHAR)
                    fi
                fi
                echo $RAW_FIELD >> $OUTPUT
            fi
        fi
    done <$INI_FILE
}

ini() {
    case $1 in
        "-l" | "--list-sections")
            ACTION="LIST-SECTIONS"
            list_sections "$@"
            ;;
        "-f" | "--list-fields")
            ACTION="LIST-FIELDS"
            list_fields "$@"
            ;;
        "-g" | "--get" | "--get-value")
            ACTION="GET-VALUE"
            get_value "$@"
            ;;
        *)
            echo "Unknown action."
            ;;
    esac
}



construct_version_link_on_linux() {
    MACHINE_TYPE=$(uname -m)

    case $MACHINE_TYPE in
        "x86" | "x86_64" | "riscv64" | "armv7a" | "aarch64" | "loongarch64") ;;

        *)
            echo "error: unsupported architecture ($MACHINE_TYPE)."
            exit -1
            ;;
    esac

    echo "https://ziglang.org/download/$1/zig-linux-$MACHINE_TYPE-$1.tar.xz"
}

construct_version_link_on_darwin() {
    MACHINE_TYPE=$(uname -m)

    # This check only exists for completeness.
    # Most users of Darwin-based operating systems use aarch64-based systems,
    # while some still use x86_64. Virtually none use PowerPC anymore.
    case $MACHINE_TYPE in
        "aarch64" | "x86_64") ;;

        *)
            echo "error: unsupported machine architecture ($MACHINE_TYPE)"
            exit -1
            ;;
    esac

    echo "https://ziglang.org/download/$1/zig-macos-$MACHINE_TYPE-$1.tar.xz"
}

construct_version_link_on_freebsd() {
    MACHINE_TYPE=$(uname -m)

    case $MACHINE_TYPE in
        "x86_64") ;;

        *)
            echo "error: only x86_64 is supported on freebsd."
            exit -1
            ;;
    esac

    echo "https://ziglang.org/download/$1/zig-freebsd-$MACHINE_TYPE-$1.tar.xz"
}

construct_version_link() {
    KERNEL_NAME=$(uname -s)

    case $KERNEL_NAME in
        "Linux")
            construct_version_link_on_linux $1
            ;;
        "Darwin")
            construct_version_link_on_darwin $1
            ;;
        "FreeBSD")
            construct_version_link_on_freebsd $1
            ;;
    esac
}

fetch_version() {
    VERSIONS_PATH=$HERE/.build/cache/versions

    if [[ ! -d "$VERSIONS_PATH/$1" ]];
    then
        mkdir -p $HERE/.build/cache/download/versions/

        # Downlaod the comiler of that version
        cd $HERE/.build/cache/download/versions
        wget -O  zig.tar.xz $(construct_version_link $1) -q

        if [[ $? != 0 ]];
        then
            return 1
        fi


        # Unpack the compiler to the versions directory
        mkdir -p $VERSIONS_PATH/$1
        xz -d zig.tar.xz
        tar --strip-components=1 -xf zig.tar -C $HERE/.build/cache/versions/$1
        rm -r $HERE/.build/cache/download/versions
        cd $HERE
    fi
}



initialize_project() {
    printf "Project Name: "
    read PROJECT_NAME
    if [[ "$PROJECT_NAME" == "" ]];
    then
        echo "Invalid name. Exiting..."
        exit 0
    fi

    printf "Language Version (default: 0.14.0): "
    read WANTED_LANGUAGE_VERSION
    if [[ "$WANTED_LANGUAGE_VERSION" == "" ]];
    then
        WANTED_LANGUAGE_VERSION="0.14.0"
    fi

    if [[ ! -d "$HERE/.build" ]];
    then
        mkdir $HERE/.build
        echo -e "cache\n" > $HERE/.build/.gitignore
    fi

    fetch_version

    if [[ $? != 0 ]];
    then
        echo "error: failed downloading zig compiler."
        return
    fi

    echo "[Project]" > $HERE/.build/manifest.ini
    echo "Project-Name = \"$PROJECT_NAME\"" >> $HERE/.build/manifest.ini
    echo "Language-Version = \"$WANTED_LANGUAGE_VERSION\"" >> $HERE/.build/manifest.ini

    echo ".zig-cache" >> $HERE/.gitignore
    echo "zig-out" >> $HERE/.gitignore

    $HERE/.build/cache/versions/$WANTED_LANGUAGE_VERSION/zig $@
}

if [[ $# -lt 1 ]];
then
    echo "error: no action given. try: $0 init"
    exit -1
fi

case "$1" in
    "init")
        initialize_project $@
        exit
        ;;
esac

LANGUAGE_VERSION=$(ini -g Project:Language-Version $HERE/.build/manifest.ini)
"$HERE/.build/cache/versions/$LANGUAGE_VERSION/zig" $@
