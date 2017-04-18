# LinkCheck - check URLs in an EPrints repository

This script and plug-in checks all the URL fields of a repository and updates the issue 
list. It does so for daily batches of eprint items or for all items. The field names are 
taken from a configuration file. Upon request, it also produces a report of the
checked URLs sorted by HTTP status code.


## Installation

Copy the contents of the bin and lib directories to the respective {eprints_root}/bin and
{eprints_root}/lib directories. 
Copy the cfg/cfg.d/z_linkcheck.pl file to {eprints_root}/archives/{yourarchive}/cfg/cfg.d/
z_linkcheck.pl.
Optionally, if you want to have improved help for Admin > Issues search, copy the 
phrases files cfg/lang/{language}/phrases/eprint_item_issues.xml to their respective 
{eprints_root}/archives/{yourarchive}/cfg/lang/{language}/phrases/eprint_item_issues.xml.

## Configuration

Edit the {eprints_root}/archives/{yourarchive}/cfg/cfg.d/z_linkcheck.pl file 
according to your requirements.

Restart the web server.


## Test your setup

Test your setup by checking an eprint that has an invalid, a working or a non-functioning 
URL:

```sudo -u apache {eprints_root}/bin/linkcheck {repo} {eprintid} --verbose --report```


## Finding invalid and non-functioning URLs in the item issues

LinkCheck updates your item issues table with a issue type `check_url_status` for 
non-functioning URLs (format-valid URLs that yield a HTTP status code <> 200) or 
`invalid_url` for URLs that have an invalid format (e.g. a typo into the protocol,
such as htpp). 

Detected issues are marked with issue status `reported`.
Issues where URLs were fixed (either removed or corrected) are marked with issue status 
`resolved` upon subsequent run of linkcheck.

To find issues, login to your repository as administrator. Goto Admin > Search Issues, 
and search by `check_url_status` or `invalid_url` in the Issue Type field.

However, we also recommend to use the `--report` option of linkcheck that produces a neat 
report sorted by HTTP status code, eprintid and URL, because
- Search Issues does not provide a nice overview of the issues because it reports by 
  eprint item, not by issue; there should be an option to group issues by issue description.
- there is no way to reset an issue manually after an URL has been corrected 
  (only by running linkcheck again)

The report sorted by URL allows to find patterns of URLs that can be fixed by a batch
procedure.


## Running linkcheck

Depending on the number of URLs you have in your repository, you may either carry out 
nightly runs (e.g. as a cron job), which does a daily segment of your repository

```linkcheck {repo} --report >{eprints_root}/var/linkcheck.txt```

or a full run using `--all`

```linkcheck {repo} --all --report >{eprints_root}/var/linkcheck.txt```


A full run may take a long, long time (days).


## Todo

Instead of using the separate linkcheck script, the issues audit procedure could be 
invoked (see https://wiki.eprints.org/w/Issues_audit and  
https://wiki.eprints.org/w/Using_Issues_for_Quality_Control ). Issues audit is usually 
run nightly and processes all eprint item; however, depending on size of a repository and 
the quality of the URLs, a link check may not finish in good time. We have thought about 
this option, but decided to create a script that can be run separately and can process 
URLs in smaller chunks.
For small repositories, issues audit might be an alternative and in some time we may
provide an issues plugin for URL checks.











