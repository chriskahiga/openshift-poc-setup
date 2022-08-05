source $WORK_DIR/helper.sh
on_error() {
        if [ "$1" -ne 0 ]; then
                [[ ! -z "$2" ]] && { failed_logger ;echo -e "$2"; } || echo "Command Failed"
                exit 1
        fi
}
