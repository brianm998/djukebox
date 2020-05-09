#!/bin/bash

find $1 -name '*.mp3' -exec perl ~/git/djukebox/mp3.pl '{}' ';' -print
curl -H 'Authorization: 0a50261ebd1a390fed2bf326f2673c145582a6342d523204973d0219337f81616a8069b012587cf5635f6925f1b56c360230c19b273500ee013e030601bf2425' -H "Path: $1" http://192.168.1.164:8080/discover
