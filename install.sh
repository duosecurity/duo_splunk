#!/bin/sh

# default splunk install directory
SPLUNK=/opt/splunk

while getopts d:i:s:a:h: o
do  
    case "$o" in
        d)  SPLUNK="$OPTARG";;
        i)  IKEY="$OPTARG";;
        s)  SKEY="$OPTARG";;
        a)  AKEY="$OPTARG";;
        h)  HOST="$OPTARG";;
        [?]) printf >&2 "Usage: $0 [-d splunk directory] -i ikey -s skey -a akey -h host\n"
             printf >&2 "ikey, skey, and host can be found in Duo account's administration panel at admin.duosecurity.com\n"
             printf >&2 "see http://www.duosecurity.com/docs/duoweb#generate_an_application_key for instructions on how to generate an akey\n"
             exit 1;;
    esac
done

if [ -z $IKEY ]; then echo "Missing -i (Duo integration key)"; exit 1; fi
if [ -z $SKEY ]; then echo "Missing -s (Duo secret key)"; exit 1; fi
if [ -z $AKEY ]; then echo "Missing -a (Duo application key) See http://www.duosecurity.com/docs/duoweb#generate_an_application_key for instructions."; exit 1; fi
if [ -z $HOST ]; then echo "Missing -h (Duo API hostname)"; exit 1; fi

echo "Installing Duo integration to $SPLUNK..."

# patch
patch $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py account.py.diff

echo "Copying in Duo integration files..."

# install duoauth template
cp duoauth.html $SPLUNK/share/splunk/search_mrsparkle/templates/account/

# install Duo javascript
cp duo.web.bundled.min.js $SPLUNK/share/splunk/search_mrsparkle/exposed/js/contrib/

# install Duo Web SDK
cp duo_web.py $SPLUNK/lib/python2.7/site-packages/

# configure account.py
echo "Configuring Duo API keys..."
sed -i "s/YOUR_DUO_IKEY/$IKEY/g" $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py
sed -i "s/YOUR_DUO_SKEY/$SKEY/g" $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py
sed -i "s/YOUR_DUO_AKEY/$AKEY/g" $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py
sed -i "s/YOUR_DUO_HOST/$HOST/g" $SPLUNK/lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py

# restart splunk web
echo 'Restarting splunkweb...'
$SPLUNK/bin/splunk restart splunkweb

echo "Done installing duo_splunk!"
