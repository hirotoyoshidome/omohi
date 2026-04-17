#!/usr/bin/env bash

session_name "basic-track-add-commit"
set_step_timeout 10

file_write "note.txt" $'first version\n'
omohi_exec track "$(work_path "note.txt")"
omohi_exec add "$(work_path "note.txt")"
omohi_exec commit -m "capture initial note"
capture_commit_id COMMIT_ID
omohi_exec show "$COMMIT_ID"

file_append "note.txt" $'second version\n'
omohi_exec status
omohi_exec add "$(work_path "note.txt")"
omohi_exec_expect "2" commit
omohi_exec commit -m "capture second note"
omohi_exec find --limit 10
