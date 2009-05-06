# switch_java_functions - functions for switching Java alternatives
# Copyright (C) 2007 Red Hat, Inc.

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; see the file COPYING.  If not, write to the
# Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 USA.

import gettext
import os
import os.path
import re

PROGNAME = 'system-switch-java'
COPYRIGHT = 'Copyright (C) 2007 Red Hat, Inc.'
AUTORS = ['Thomas Fitzsimmons <fitzsim@redhat.com>']
VERSION = '1.1.4'

# Internationalization.
gettext.bindtextdomain(PROGNAME, '/usr/share/locale')
gettext.textdomain(PROGNAME)
_ = gettext.gettext

TEXT_MESSAGE = _('''\
display text interface even if graphics display is available\
''')
PARSE_ERROR_MESSAGE = _('''\
An attempt to parse /var/lib/alternatives/java failed.\
''')
NO_JAVA_MESSAGE = _('''\
No supported Java packages were found.  A supported Java package is\
 one that installs a file of the form:

/usr/lib/jvm/jre-$version-$vendor/bin/java

For example, java-1.4.2-gcj-compat is a supported package because it\
 installs:

/usr/lib/jvm/jre-1.4.2-gcj/bin/java\
''')
INSTRUCTION_MESSAGE = _('Select the default Java toolset for the system.')
TITLE_MESSAGE = _('Java Toolset Configuration')
SELECTION_MESSAGE = _('Installed Java Toolsets')
ROOT_MESSAGE = _('''\
The default Java toolset can only be configured by the root user.\
''')
OK_MESSAGE = _('OK')
CLOSE_MESSAGE = _('Close')
JAVA_PATH = '/etc/alternatives/java'
ALTERNATIVES = {}
JAVA = {}
JRE = {}
JCE = {}
JAVAC = {}
SDK = {}
PLUGIN = {}
JAVADOCDIR = {}

class JavaOpenError(Exception):
    pass
class JavaParseError(Exception):
    pass

def switch_java(java):
    vendor, version, arch = get_java_split(java)
    # There are problems with the jre_ibm, jre_1.4.2, java_sdk,
    # java_sdk_1.4.2 and libjavaplugin.so alternatives in the JPackage
    # java-1.4.2-ibm and java-1.5.0-ibm packages, but not in the RHEL
    # ones.  We suppress error output from the alternatives commands
    # so that JPackage users won't be alarmed.  The only consequence
    # for them is that the seldom-used /usr/lib/jvm/jre-ibm,
    # /usr/lib/jvm/jre-1.4.2, /usr/lib/jvm/java-1.4.2 and
    # /usr/lib/jvm/java-ibm symlinks will not be updated.  In the case
    # of the plugin, JPackage and Red Hat plugin packages are
    # incompatible anyway, so failing to set an alternative will not
    # cause additional problems.
    suppress = ''
    if vendor == 'ibm':
        suppress = ' >/dev/null 2>&1'
    os.system('/usr/sbin/alternatives --set java ' + JAVA[java])
    os.system('/usr/sbin/alternatives --set jre_' + vendor
              + ' ' + JRE[java] + suppress)
    os.system('/usr/sbin/alternatives --set jre_' + version
              + ' ' + JRE[java] + suppress)
    if JCE[java] != None:
        os.system('/usr/sbin/alternatives --set jce_' + version
                  + '_' + vendor + '_local_policy' + arch + ' ' + JCE[java])
    if JAVAC[java] != None:
        os.system('/usr/sbin/alternatives --set javac ' + JAVAC[java])
        os.system('/usr/sbin/alternatives --set java_sdk_' + vendor
                  + ' ' + SDK[java] + suppress)
        os.system('/usr/sbin/alternatives --set java_sdk_' + version
                  + ' ' + SDK[java] + suppress)
    if PLUGIN[java] != None:
        os.system('/usr/sbin/alternatives --set libjavaplugin.so' + arch
                  + ' ' + PLUGIN[java])
    if JAVADOCDIR[java] != None:
        os.system('/usr/sbin/alternatives --set javadocdir '
                  + JAVADOCDIR[java])

def get_java_identifiers():
    java_identifiers = []
    best_identifier = None
    alternatives, best = get_alternatives('java')
    java_expression = re.compile('/usr/lib/jvm/jre-([^/]*)/bin/java')
    for alternative in alternatives:
        java_search = java_expression.search(alternative)
        if java_search == None:
            # Skip unrecognized java alternative.
            continue
        java = java_search.group(1)
        java_identifiers.append(java)
    if len(java_identifiers) > 0:
        # FIXME: best needs to be calculated as the best of the
        # recognized java alternatives.  Otherwise a custom-installed
        # highest-priority java alternative will result in
        # java_identifiers[best] causing an array index out-of-bounds
        # error.  custom-installed java alternatives are rare (maybe
        # non-existant) so this FIXME is low priority.  The best fix
        # is probably to pass the recognizing re expression to
        # get_alternatives.
        best_identifier = java_identifiers[best]
        java_identifiers.sort(cmp, get_sorting_name)
        initialize_alternatives_dictionaries(java_identifiers)
    return java_identifiers, best_identifier

def get_plugin_alternatives(plugin_alternatives, arch):
    try:
        alternatives, best = get_alternatives('libjavaplugin.so' + arch)
        plugin_expression = re.compile('/usr/lib/jvm/jre-([^/]*)/')
        for alternative in alternatives:
            java_search = plugin_expression.search(alternative)
            if java_search == None:
                # Skip unrecognized libjavaplugin.so alternative.
                continue
            java = java_search.group(1)
            plugin_alternatives[java] = alternative
    except JavaParseError:
        # Ignore libjavaplugin.so parse errors.
        pass
    except JavaOpenError:
        # No libjavaplugin.so alternatives were found.
        pass
    return plugin_alternatives

def get_javadocdir_alternatives():
    javadocdir_alternatives = {}
    try:
        alternatives, best = get_alternatives('javadocdir')
        javadocdir_expression = re.compile('/usr/share/javadoc/java-([^/]*)/')
        for alternative in alternatives:
            java_search = javadocdir_expression.search(alternative)
            if java_search == None:
                # Skip unrecognized javadocdir alternative.
                continue
            java = java_search.group(1)
            javadocdir_alternatives[java] = alternative
    except JavaParseError:
        # Ignore javadocdir parse errors.
        pass
    except JavaOpenError:
        # No javadocdir alternatives were found.
        pass
    return javadocdir_alternatives

def get_alternatives(master):
    alternatives = []
    highest_priority = -1
    best = -1
    slave_line_count = 0
    # Skip mode and master symlink lines.
    first_slave_index = 2
    index = first_slave_index
    try:
        file = open('/var/lib/alternatives/' + master, 'r')
    except:
        raise JavaOpenError
    try:
        lines = file.readlines()
        # index points to first slave line.
        line = lines[index]
        # Count number of slave lines to ignore.
        while line != '\n':
            index = index + 1
            line = lines[index]
        # index points to blank line separating slaves from target.
        slave_line_count = (index - first_slave_index) / 2
        index = index + 1
        # index points to target.
        while index < len(lines):
            line = lines[index]
            # Accept trailing blank lines at the end of the file.
            # Debian's update-alternatives requires this.
            if line == '\n':
                break
            # Remove newline.
            alternative = line[:-1]
            # Exclude alternative targets read from
            # /var/lib/alternatives/$master that do not exist in the
            # filesystem.  This inconsistent state can be the result
            # of an rpm post script failing.
            append = False
            if os.path.exists(alternative):
                append = True
                alternatives.append(alternative)
            index = index + 1
            # index points to priority.
            line = lines[index]
            if append:
                priority = int(line[:-1])
                if priority > highest_priority:
                    highest_priority = priority
                    best = len(alternatives) - 1
            index = index + 1
            # index points to first slave.
            index = index + slave_line_count
            # index points to next target or end-of-file.
    except:
        raise JavaParseError
    return alternatives, best

def get_sorting_name(alternative):
    vendor, version, arch = get_java_split(alternative)
    return vendor + version + arch

def initialize_alternatives_dictionaries(java_identifiers):
    plugin_alternatives = get_plugin_alternatives({}, '')
    javadocdir_alternatives = get_javadocdir_alternatives()
    arch_found = False
    for java in java_identifiers:
        vendor, version, arch = get_java_split(java)
        JAVA[java] = '/usr/lib/jvm/jre-' + java + '/bin/java'
        # Command-to-alternative-name map to set default alternative.
        ALTERNATIVES[JAVA[java]] = java
        JRE[java] = '/usr/lib/jvm/jre-' + java
        jce = '/usr/lib/jvm-private/java-' + java\
              + '/jce/vanilla/local_policy.jar'
        if os.path.exists(jce):
            JCE[java] = jce
        else:
            JCE[java] = None
        javac = '/usr/lib/jvm/java-' + java + '/bin/javac'
        if os.path.exists(javac):
            JAVAC[java] = javac
            SDK[java] = '/usr/lib/jvm/java-' + java
        else:
            JAVAC[java] = None
            SDK[java] = None
        if arch != '' and not arch_found:
            plugin_alternatives = get_plugin_alternatives(plugin_alternatives,
                                                          arch)
            arch_found = True
        PLUGIN[java] = None
        if java in plugin_alternatives:
            PLUGIN[java] = plugin_alternatives[java]
        JAVADOCDIR[java] = None
        if java in javadocdir_alternatives:
            JAVADOCDIR[java] = javadocdir_alternatives[java]

def get_default_java_command():
    if os.path.exists(JAVA_PATH) and os.path.islink(JAVA_PATH):
        return os.readlink(JAVA_PATH)
    else:
        return None

def get_pretty_names(alternative_names):
    pretty_names = {}
    for java in alternative_names:
        vendor, version, arch = get_java_split(java)
        if vendor == 'sun' or vendor == 'blackdown':
            pretty_names[java] = vendor.capitalize() + ' ' + version
        elif vendor == 'icedtea':
            pretty_names[java] = 'IcedTea' + ' ' + version
        elif vendor == 'openjdk':
            pretty_names[java] = 'OpenJDK' + ' ' + version
        else:
            pretty_names[java] = vendor.upper() + ' ' + version
        if arch != '':
            pretty_names[java] = pretty_names[java] + ' ' + '64-bit'
    return pretty_names

def get_java_split(java):
    vendor_arch = java.split('-')[1].split('.')
    vendor = vendor_arch[0]
    arch = ''
    if len(vendor_arch) > 1:
        arch = '.' + vendor_arch[1]
    version = java.split('-')[0]
    return vendor, version, arch
