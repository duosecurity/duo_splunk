#!/bin/sh

# default splunk install directory
SPLUNK=/opt/splunk

while getopts d: o
do  
    case "$o" in
        d)  SPLUNK="$OPTARG";;
        [?]) printf >&2 "Usage: $0 [-d splunk directory]\n"
             exit 1;;
    esac
done

echo "Attempting to uninstall the Duo integration from $SPLUNK..."

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

mv $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/.old_account.py $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py
if [ $? != 0 ]; then
	echo "Backup file no longer exists, cannot uninstall the Duo integration."
	exit 1
fi

# Try to remove cache if it exists
if [ -e $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.pyo ]; then
	echo "Deleting web app cache..."
	rm $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.pyo
fi

# And remove other splunk files.
if [ -e $SPLUNK/share/splunk/search_mrsparkle/templates/account/duoauth.html ]; then
	rm $SPLUNK/share/splunk/search_mrsparkle/templates/account/duoauth.html 
fi

if [ -e $SPLUNK/share/splunk/search_mrsparkle/exposed/js/contrib/duo.web.bundled.min.js ]; then
	rm $SPLUNK/share/splunk/search_mrsparkle/exposed/js/contrib/duo.web.bundled.min.js 
fi

if [ -e $SPLUNK/lib/python2.7/site-packages/duo_web.py ]; then
	rm $SPLUNK/lib/python2.7/site-packages/duo_web.py
fi

echo 'Restarting splunkweb...'
$SPLUNK/bin/splunk restart splunkweb

echo "Duo integration successfully uninstalled."
