#!/bin/bash
cat $1 | xargs rpm -Uvh --force || cat $1 | xargs rpm -Uvh --nodeps --force
