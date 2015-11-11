#!/bin/sh

# default splunk install directory
SPLUNK=/opt/splunk
AKEY=`python -c "import hashlib, os;  print hashlib.sha1(os.urandom(32)).hexdigest()"`
FAILOPEN="False"
TIMEOUT="15"


while getopts d:i:s:h:f:t: o
do  
    case "$o" in
        d)  SPLUNK="$OPTARG";;
        i)  IKEY="$OPTARG";;
        s)  SKEY="$OPTARG";;
        h)  HOST="$OPTARG";;
        f)  FAILOPEN="$OPTARG";;
        t)  TIMEOUT="$OPTARG";;
        [?]) printf >&2 "Usage: $0 [-d splunk directory] -i ikey -s skey -h host [-f (True|False)] [-t seconds] \n"
             printf >&2 "ikey, skey, and host can be found in Duo account's administration panel at admin.duosecurity.com\n"
             printf >&2 'Failopen (-f) should be set to '\''True'\'' or '\''False'\'', default to '\''False'\''\n'
             printf >&2 'Timeout (-t) is number of seconds to wait to see if Duo is available before invoking failmode.\n'
             exit 1;;
    esac
done
SPLUNK_ERROR="The directory ($SPLUNK) does not look like a Splunk installation. Use the -d option to specify where Splunk is installed."

# Input validation - normalize the Failmode argument to
# begin with an uppercase letter, and make the rest lowercase.
if [ -n "$FAILOPEN" ]; then
    FAILOPEN=$(echo ${FAILOPEN} | awk '
        BEGIN { IGNORECASE=1 }
        { if ($0 ~ /^true$/) {
            print "True"
            exit 0
          }
          if ($0 ~ /^false$/) {
            print "False"
            exit 0
          }
        }
        END {
            exit 1
        }')
fi

if [ "$FAILOPEN" != 'True' -a "$FAILOPEN" != 'False' ]; then
    echo 'Invalid argument: -f (True | False)'
    exit 1
fi

# Input validation - timeout must be a whole non-negative number
if [ "$TIMEOUT" -ge 0 ] 2>/dev/null; then
    :
else
    echo "Invalid argument: -t must specify a number, not '$TIMEOUT'"
    exit 1
fi

if [ ! -d $SPLUNK ]; then
    echo "$SPLUNK_ERROR"
    exit 1
fi
if [ ! -e $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py ]; then
    echo "$SPLUNK_ERROR"
    exit 1
fi
if [ ! -d $SPLUNK/share/splunk/search_mrsparkle/templates/account/ ]; then
    echo "$SPLUNK_ERROR"
    exit 1
fi
if [ ! -d $SPLUNK/share/splunk/search_mrsparkle/exposed/js/contrib/ ]; then
    echo "$SPLUNK_ERROR"
    exit 1
fi
if [ ! -d $SPLUNK/lib/python2.7/site-packages/ ]; then
    echo "$SPLUNK_ERROR"
    exit 1
fi

# make sure it looks like Splunk has not been patched before
# Check for current patched version
if grep -q 'DUO SECURITY MODIFICATIONS VER 2' "$SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py"; then
    echo 'It looks like Splunk has already been patched to integrate with Duo.'
    echo 'Please contact support@duosecurity.com if you are having trouble'
    echo 'exiting'
    exit 1
fi

UPGRADE=0
# Check for upgrade
if grep -q 'DUO SECURITY MODIFICATIONS' "$SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py"; then
    echo 'It looks like Splunk has already been patched to integrate with Duo.'
    echo 'Upgrading existing installation.'
    UPGRADE=1
    # Read configuration items out of the existing patched account.py file, if the user didn't specify them already.
    ACCOUNT_PYTHON="${SPLUNK}/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py"
    if [ -z "$IKEY" ]; then
        IKEY=$(sed -n 's/^DUO_IKEY *= *'\''\(.*\)'\''$/\1/ ; T ; p; q' "$ACCOUNT_PYTHON")
    fi
    if [ -z "$SKEY" ]; then
        SKEY=$(sed -n 's/^DUO_SKEY *= *'\''\(.*\)'\''$/\1/ ; T ; p; q' "$ACCOUNT_PYTHON")
    fi
    if [ -z "$HOST" ]; then
        HOST=$(sed -n 's/^DUO_HOST *= *'\''\(.*\)'\''$/\1/ ; T ; p; q' "$ACCOUNT_PYTHON")
    fi

fi

if [ -z "$IKEY" ]; then echo 'Missing -i (Duo integration key)'; exit 1; fi
if [ -z "$SKEY" ]; then echo 'Missing -s (Duo secret key)'; exit 1; fi
if [ -z "$HOST" ]; then echo 'Missing -h (Duo API hostname)'; exit 1; fi

echo "Installing Duo integration to $SPLUNK..."


# Figure out what version to patch
if grep -q 'VERSION=4' "$SPLUNK/etc/splunk.version" ; then
    if [ $UPGRADE -eq 1 ] ; then
        echo 'Duo is already installed, and no upgrade exists for splunk version 4.'
        echo 'Exiting.'
        exit 0
    fi
	echo "Using patch for version 4..."
	PATCH="account.py.4.diff"
fi

if grep -q 'VERSION=5' "$SPLUNK/etc/splunk.version" ; then
	echo "Using patch for version 5..."
	PATCH="account.py.5.diff"
fi

if grep -q 'VERSION=6' "$SPLUNK/etc/splunk.version" ; then
	echo "Using patch for version 6..."
	PATCH="account.py.6.diff"
fi

if grep -q 'VERSION=6.3' "$SPLUNK/etc/splunk.version" ; then
	echo "Using patch for version 6.3..."
	PATCH="account.py.63.diff"
	PATCH2="decorators.py.63.diff"
fi

if [ -z "$PATCH" ]; then
    echo 'Patching this version of Splunk will not work, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

# Running account python file
ACCOUNT_PY_FILE="$SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py"
# Splunk's original file
OLD_ACCOUNT_PY_FILE="$SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/.old_account.py"
# Duo's version 1 patched file
OLD_ACCOUNT_PY_FILE_PATCHED="$SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/.old_account.py.duo_patched"

# Store a command to either restore the original account.py file, or do nothing, depending on
# whether Duo has patched this splunk install already or not.
COPY_ACCOUNT_PY_FILE=""
# Remember which file we want to test the patch against
PATCH_TEST_ACCOUNT_PY_FILE="$ACCOUNT_PY_FILE"
# Remember which file to restore from in case of failure
ACCOUNT_PY_BACKUP_FILE="$OLD_ACCOUNT_PY_FILE"

if [ -f "$OLD_ACCOUNT_PY_FILE" ]; then
    # Keep a copy of the patched account.py file
    cp -f "$ACCOUNT_PY_FILE" "$OLD_ACCOUNT_PY_FILE_PATCHED"

    # Update the variables to handle version 2 update case.
    COPY_ACCOUNT_PY_FILE="cp -f $OLD_ACCOUNT_PY_FILE $ACCOUNT_PY_FILE"
    PATCH_TEST_ACCOUNT_PY_FILE="$OLD_ACCOUNT_PY_FILE"
    ACCOUNT_PY_BACKUP_FILE="$OLD_ACCOUNT_PY_FILE_PATCHED"
fi

# test patch against splunk's unmodified file.
if ! patch --dry-run "$PATCH_TEST_ACCOUNT_PY_FILE" "$PATCH" > /dev/null; then
    echo 'Patching Splunk will not work, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

# Make a backup and actually patch if the dry run was successful
cp -f "$ACCOUNT_PY_FILE" "$ACCOUNT_PY_BACKUP_FILE"

# Copy back the unmodified account.py if needed, and proceed with install.
if ! ${COPY_ACCOUNT_PY_FILE}; then
    echo 'Failed to copy the unmodified account.py for patching.  Please contact support@duosecurity.com'
    exit 1
fi

if ! patch "$ACCOUNT_PY_FILE" "$PATCH"; then
	mv "$ACCOUNT_PY_BACKUP_FILE" "$ACCOUNT_PY_FILE"
    echo 'Patching Splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

if [ "$PATCH2" ]; then
    # Running decorators python file
    DECORATORS_PY_FILE="$SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/lib/decorators.py"
    # Splunk's original file
    OLD_DECORATORS_PY_FILE="$SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/lib/.old_decorators.py"
    # Duo's version 1 patched file
    OLD_DECORATORS_PY_FILE_PATCHED="$SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/lib/.old_decorators.py.duo_patched"

    # Store a command to either restore the original decorators.py file, or do nothing, depending on
    # whether Duo has patched this splunk install already or not.
    COPY_DECORATORS_PY_FILE=""
    # Remember which file we want to test the patch against
    PATCH_TEST_DECORATORS_PY_FILE="$DECORATORS_PY_FILE"
    # Remember which file to restore from in case of failure
    DECORATORS_PY_BACKUP_FILE="$OLD_DECORATORS_PY_FILE"

    if [ -f "$OLD_DECORATORS_PY_FILE" ]; then
        # Keep a copy of the patched decorators.py file
        cp -f "$DECORATORS_PY_FILE" "$OLD_DECORATORS_PY_FILE_PATCHED"

        # Update the variables to handle version 2 update case.
        COPY_DECORATORS_PY_FILE="cp -f $OLD_DECORATORS_PY_FILE $DECORATORS_PY_FILE"
        PATCH_TEST_DECORATORS_PY_FILE="$OLD_DECORATORS_PY_FILE"
        DECORATORS_PY_BACKUP_FILE="$OLD_DECORATORS_PY_FILE_PATCHED"
    fi

    # test patch against splunk's unmodified file.
    if ! patch --dry-run "$PATCH_TEST_DECORATORS_PY_FILE" "$PATCH2" > /dev/null; then
        echo 'Patching Splunk will not work, please contact support@duosecurity.com'
        echo 'exiting'
        exit 1
    fi

    # Make a backup and actually patch if the dry run was successful
    cp -f "$DECORATORS_PY_FILE" "$DECORATORS_PY_BACKUP_FILE"

    # Copy back the unmodified decorators.py if needed, and proceed with install.
    if ! ${COPY_DECORATORS_PY_FILE}; then
        echo 'Failed to copy the unmodified decorators.py for patching.  Please contact support@duosecurity.com'
        exit 1
    fi

    if ! patch "$DECORATORS_PY_FILE" "$PATCH2"; then
        mv "$DECORATORS_PY_BACKUP_FILE" "$DECORATORS_PY_FILE"
        echo 'Patching Splunk failed, please contact support@duosecurity.com'
        echo 'exiting'
        exit 1
    fi
fi

echo "Copying in Duo client python..."
cp -r ./duo_client_python/duo_client "$SPLUNK/lib/python2.7/site-packages/"

echo "Copying in Duo integration files..."

# install duoauth template
if ! cp duoauth.html "$SPLUNK/share/splunk/search_mrsparkle/templates/account/"; then
    echo 'Patching Splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

# install Duo javascript
if ! cp duo.web.bundled.min.js "$SPLUNK/share/splunk/search_mrsparkle/exposed/js/contrib/"; then
    echo 'Patching Splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

# install Duo Web SDK
if ! cp duo_web.py "$SPLUNK/lib/python2.7/site-packages/"; then
    echo 'Patching Splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

CRED_PY_FILE=$ACCOUNT_PY_FILE
if [ "$PATCH2" ]; then
    CRED_PY_FILE=$DECORATORS_PY_FILE
fi

# configure account.py
if ! sed -i -e "s/YOUR_DUO_IKEY/$IKEY/g" "$CRED_PY_FILE"; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

if ! sed -i -e "s/YOUR_DUO_SKEY/$SKEY/g" "$CRED_PY_FILE"; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

if ! sed -i -e "s/YOUR_DUO_AKEY/$AKEY/g" "$CRED_PY_FILE"; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

if ! sed -i -e "s/YOUR_DUO_HOST/$HOST/g" "$CRED_PY_FILE"; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

if ! sed -i -e "s/YOUR_DUO_TIMEOUT/$TIMEOUT/g" "$CRED_PY_FILE"; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

if ! sed -i -e "s/YOUR_DUO_FAILOPEN/$FAILOPEN/g" "$CRED_PY_FILE"; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi



# restart splunk web
echo 'Restarting splunkweb...'
$SPLUNK/bin/splunk restart splunkweb

echo "Done installing duo_splunk!"
