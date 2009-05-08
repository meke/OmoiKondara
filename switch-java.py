#!/usr/bin/python

import os
import sys
import commands
from optparse import OptionParser
from switch_java_functions import *

def main():
    parser = OptionParser()
    parser.add_option('-j', '--jvm', dest='jvm',
                      help='set java virtual machine (1.6.0-openjdk or 1.5.0-gcj)',
                      metavar='JVM')
    parser.add_option('-c', '--current', action="store_true", dest='current',
                      help='return current java virtual machine name')
    options, args = parser.parse_args()

    java_identifiers = []
    best_identifier = ''
    try:
        java_identifiers, best_identifier = get_java_identifiers()
    except JavaParseError:
        print >>sys.stderr, PARSE_ERROR_MESSAGE
        sys.exit(1)
    except JavaOpenError:
        pass
    if len(java_identifiers) == 0:
        print >>sys.stderr, NO_JAVA_MESSAGE
        sys.exit(1)
    default_java_command = get_default_java_command()
    if default_java_command not in JAVA.values():
        default_java_command = JAVA[best_identifier]
    default_java = ALTERNATIVES[default_java_command]

    if options.current:
        print default_java
        sys.exit(0)
    if options.jvm != '1.6.0-openjdk' and options.jvm != '1.5.0-gcj':
        print >>sys.stderr, 'We can use 1.6.0-openjdk or 1.5.0-gcj only.'
        sys.exit(1)

    if options.jvm == '1.6.0-openjdk' and commands.getoutput('arch') == 'x86_64':
        options.jvm = '1.6.0-openjdk.x86_64'

    switch_java(options.jvm)
    print 'switched to', options.jvm

if __name__ == '__main__':
    main()
    sys.exit(0)
