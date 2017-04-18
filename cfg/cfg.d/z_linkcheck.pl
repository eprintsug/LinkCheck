# Linkcheck configuration
#
$c->{plugins}->{"LinkCheck::LinkCheck"}->{params}->{disable} = 0;
$c->{plugins}->{"LinkCheck::LinkCheck"}->{params}->{fieldnames} = [ 'official_url', 'related_url' ];

#
# Filter rules for URLs that need not to be processed because they are generally known
# as stable. In a filter rule, a beginning of a URL can be specified. E.g., the rule
# "http://opac.nebis.ch/F" skips all URLs that start with this string. 
#
$c->{plugins}->{"LinkCheck::LinkCheck"}->{params}->{url_filterrules} = [ 
  'http://arxiv.org/abs/',
  'https://doi.org/',
  'http://dx.doi.org/',
  'http://opac.nebis.ch/F/',
  'https://www.alexandria.unisg.ch/',
  'http://www.recherche-portal.ch/',
];

