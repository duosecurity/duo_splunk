#duo_splunk
Duo two-factor authentication for Splunk
Integration documentation: <http://www.duosecurity.com/docs/splunk>
 
##Automatic Installation Instructions:

Run the install script as follows:

```
$ ./install.sh -i <your_ikey> -s <your_skey> -h <your_host> -d <splunk_location>
```

- The -d option specifies where Splunk is installed (not required, defaults to /opt/splunk)
- You can get your ikey, skey, and host from the administrative panel at http://admin.duosecurity.com. The integration type should be Web SDK.


##Manual Installation Instructions:

All paths in these instructions are relative to where your top level splunk/ directory is.

1. Apply the account.py.diff patch to lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py

2. Edit lib/python2.7/site-packages/splunk/appserver/mrsparkle/controllers/account.py to add your Duo account specific API keys (IKEY, SKEY, DUO_HOST, and AKEY).
    - IKEY, SKEY, DUO_HOST are all available in the Duo administrative interface if you create a new web integration.
    - See http://www.duosecurity.com/docs/duoweb#generate_an_application_key for instructions on how to generate your AKEY

3. Copy duoauth.html into share/splunk/search_mrsparkle/templates/account/

4. Copy duo.web.bundled.min.js into share/splunk/search_mrsparkle/exposed/js/contrib/

5. Copy duo_web.py into lib/python2.7/site-packages/

6. Restart splunkweb: $ bin/splunk restart splunkweb

Upon your next login you will be prompted to enroll or authenticate your user using Duo.
