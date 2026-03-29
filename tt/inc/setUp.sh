#!/usr/bin/env bash
# Twitch MP3 tagger.
# Copyright (c) 2023-2026, Rev. Duncan Ross Palmer (2E0EOL)
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     * Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#
#     * Neither the name of the the maintainer, nor the names of its contributors
#       may be used to endorse or promote products derived from this software
#       without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.


set -euo pipefail

EXE="../bin/twitch-tag-mp3"
LIBDIR="../lib"

tmpDir=$(mktemp -d)
rootDir=$(mktemp -d)

function newRIFF {
	if command -v sox >/dev/null 2>&1; then
		sox -n -r 44100 -c 2 "$tmpDir/source.wav" trim 0.0 2.0
	elif command -v arecord >/dev/null 2>&1; then
		arecord -d 2 -f S16_LE -r 44100 "$tmpDir/source.wav"
	else
		>&2 'ERROR: 💥 no recognized tools for making RIFF PCM audio files are installed'
		return 1
	fi

	return 0
}

source=''
function RIFF2MP3 {
	source="$tmpDir/source.mp3"
	if command -v lame >/dev/null 2>&1; then
		lame "$tmpDir/source.wav" "$source"
	elif command -v bladeenc >/dev/null 2>&1; then
		bladeenc "$tmpDir/source.wav" "$source"
	else
		>&2 'ERROR: 💥 no recognized tools for making MPEG II level III files are installed'
		return 1
	fi

	return 0
}

function copyFiles {
	filesNames=(
		"JohnnyEOfficial (live) 2022-03-17 20_31-45879430669-desilence"
		"JenniferRenePlays (live) 2022-03-17 00_12-45870468605"
		"LeeJOfficial (live) 2022-04-07 20_00-45169276284-desilence"
		"leejtranzalitystudios (live) 2021-08-26 19_01-43077611596"
		"Sarah_L_C (live) 2021-06-25_MP3WRAP-desilence"
		"SOTCHI_RIOT (live) 2022-05-28 16_17-45482207596-desilence"
		"swearyprincess (live) 2022-08-04 20_07-45869356460-desilence"
		"Ucron (live) 2022-10-17 00_06-40358894505-desilence"
		"2022-03-30-06-45-01-vlastimilvibes"
	)

	for fileName in "${filesNames[@]}"; do
		cp "$source" "$rootDir/$fileName.mp3"
	done
}

newRIFF
RIFF2MP3
copyFiles
