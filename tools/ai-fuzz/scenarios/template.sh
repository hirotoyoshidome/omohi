#!/usr/bin/env bash

session_name "replace-with-scenario-name"
set_step_timeout 10

file_write "note.txt" $'draft text\n'
omohi_exec track "$(work_path "note.txt")"
omohi_exec add "$(work_path "note.txt")"
omohi_exec commit -m "capture template note"

# Use *_expect helpers for intentional failures.
# Example:
# omohi_exec_expect "2" commit
