#!/bin/sh

# default splunk install directory
SPLUNK=/opt/splunk
AKEY=`python -c "import hashlib, os;  print hashlib.sha1(os.urandom(32)).hexdigest()"`

while getopts d:i:s:h: o
do  
    case "$o" in
        d)  SPLUNK="$OPTARG";;
        i)  IKEY="$OPTARG";;
        s)  SKEY="$OPTARG";;
        h)  HOST="$OPTARG";;
        [?]) printf >&2 "Usage: $0 [-d splunk directory] -i ikey -s skey -h host\n"
             printf >&2 "ikey, skey, and host can be found in Duo account's administration panel at admin.duosecurity.com\n"
             exit 1;;
    esac
done

if [ -z $IKEY ]; then echo "Missing -i (Duo integration key)"; exit 1; fi
if [ -z $SKEY ]; then echo "Missing -s (Duo secret key)"; exit 1; fi
if [ -z $HOST ]; then echo "Missing -h (Duo API hostname)"; exit 1; fi

echo "Installing Duo integration to $SPLUNK..."

SPLUNK_ERROR="The directory ($SPLUNK) does not look like a Splunk installation. Use the -d option to specify where Splunk is installed."

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
grep "DUO SECURITY MODIFICATIONS" $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py
if [ $? == 0 ]; then
    echo 'It looks like Splunk has already been patched.'
    echo 'Please contact support@duosecurity.com if you are having trouble'
    echo 'exiting'
    exit 1
fi

# test patch
patch --dry-run $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py account.py.diff
if [ $? != 0 ]; then
    echo 'Patching Splunk will not work, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

# actually patch if the dry run was successful
patch $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py account.py.diff
if [ $? != 0 ]; then
    echo 'Patching Splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

echo "Copying in Duo integration files..."

# install duoauth template
cp duoauth.html $SPLUNK/share/splunk/search_mrsparkle/templates/account/
if [ $? != 0 ]; then
    echo 'Patching Splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

# install Duo javascript
cp duo.web.bundled.min.js $SPLUNK/share/splunk/search_mrsparkle/exposed/js/contrib/
if [ $? != 0 ]; then
    echo 'Patching Splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

# install Duo Web SDK
cp duo_web.py $SPLUNK/lib/python2.7/site-packages/
if [ $? != 0 ]; then
    echo 'Patching Splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

# configure account.py
echo "Configuring Duo API keys..."
sed -i'' -e "s/YOUR_DUO_IKEY/$IKEY/g" $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py
if [ $? != 0 ]; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

sed -i'' -e "s/YOUR_DUO_SKEY/$SKEY/g" $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py
if [ $? != 0 ]; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

sed -i'' -e "s/YOUR_DUO_AKEY/$AKEY/g" $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py
if [ $? != 0 ]; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

sed -i'' -e "s/YOUR_DUO_HOST/$HOST/g" $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py
if [ $? != 0 ]; then
    echo 'Configuring duo_splunk failed, please contact support@duosecurity.com'
    echo 'exiting'
    exit 1
fi

# delete the backup file if all the sed commands were successful
BACKUP=$SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py-e
if [ -e $BACKUP ]; then
    rm -f $BACKUP
fi

# restart splunk web
echo 'Restarting splunkweb...'
$SPLUNK/bin/splunk restart splunkweb

echo "Done installing duo_splunk!"
