######################################################################
#
#  LinkCheck::LinkCheck
# 
######################################################################
#
#  Copyright 2017 University of Zurich. All Rights Reserved.
#
#  Martin Brändle
#  Zentrale Informatik
#  Universität Zürich
#  Stampfenbachstr. 73
#  CH-8006 Zürich
#
#  The plug-ins are free software; you can redistribute them and/or modify
#  them under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The plug-ins are distributed in the hope that they will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with EPrints 3; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
######################################################################


=head1 NAME

EPrints::Plugin::LinkCheck::LinkCheck - Plug-in for checking URLs.

=head1 DESCRIPTION



=head1 METHODS

=over 4

=item $plugin = EPrints::Plugin::LinkCheck::LinkCheck->new( %params )

Creates a new LinkCheck plugin.

=item check_urls

Checks the URLs of an eprint.

=item process_url( $url, $fieldname, $pos )

Processes a single URL 

=item print_report

Prints a report of all checked items, sorted by status code, item and 
url or url and item, respectively. 


=back

=cut

package EPrints::Plugin::LinkCheck::LinkCheck;

use strict;
use warnings;
use utf8;

use EPrints::Const qw( :http );
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Status;
use Data::Dumper;

use base 'EPrints::Plugin';

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new( %params );

	$self->{name} = "LinkCheck::LinkCheck";
	$self->{visible} = "all";

	return $self;
}

#
# Retrieves the URLs of an eprint and sends them to the link check procedure.
#
sub check_urls
{
	my ($self) = @_;
	
	my $dataset = $self->{dataset};
	my $eprint = $self->{eprint};
	my $param = $self->{param};
	
	# Get the field names for the fields that contain URLs and shall be processed 
	# from the configuration.
	my $fieldnames = $self->param( "fieldnames" );
	
	
	
	$self->_resolve_issues();
	
	foreach my $fieldname (@{$fieldnames})
	{
		if ($eprint->is_set( $fieldname ) )
		{
			my $field = $dataset->field( $fieldname );
			
			if ( $field->property( "multiple" ) )
			{
				$self->_fix_urls( $fieldname );
				
				my $urls = $eprint->get_value( $fieldname );

				my $pos = 0;
				foreach my $url_record (@{$urls})
				{
					my $url = $url_record->{url};
					$self->process_url( $url, $fieldname, $pos );
					$pos++;
				} 
			}
			else
			{
				my $url = $eprint->get_value( $fieldname );
				my $pos = 0;
				$self->process_url( $url, $fieldname, $pos );
			}
		}
	}
	
	return;
}

#
# Processes an URL by testing against a set of filter rules, fetching the 
# HTTP header response, processing the response and updating the list of
# eprint issues.
#
sub process_url
{
	my ( $self, $url, $fieldname, $pos ) = @_;
	
	#
	# Get filter rules for URLs that need not to be processed because they are generally known
	# as stable. In a filter rule, a beginning of a URL can be specified. E.g.  
	# the rule "http://opac.nebis.ch/F" skips all URLs that start with this string. 
	#
		
	my $url_filterrules = $self->param( "url_filterrules" );
	
	my $filter = 1;
	foreach my $url_filterrule (@{$url_filterrules})
	{
		$url_filterrule = '^' . $url_filterrule;
		my $filter_rule = qr/$url_filterrule/;
		
		$filter = 0 if ( $url =~ /$filter_rule/ );
	}
	
	if ($filter)
	{
		my $response = $self->_fetch_url( $url );
		$self->_evaluate_response( $response, $url, $fieldname );
		$self->_update_issues( $response, $url, $fieldname, $pos );
	}
	
	return;
}

#
# Fetch the URL using a HTTP HEAD or, if the HEAD method is not allowed (HTTP Status 405),
# using a HTTP GET. 
#
sub _fetch_url
{
	my ( $self, $url ) = @_;
	
	my $response = {};
	
	my $param = $self->{param};
	my $eprint = $self->{eprint};
	my $eprintid = $eprint->id;
	
	my $report = $param->{report};
	
	my $crawl_retry = $param->{crawl_retry};
	my $crawl_delay = $param->{crawl_delay};
	my $timeout = $param->{timeout};
	
	my $useragent_name = "Link Check; EPrints 3.3.x;" . $param->{base_url};
	
	my $verbose = $param->{verbose};
	my $noise = 1;
    $noise = 1 + $verbose if( $verbose );
    
    my $dump_response = $param->{dump_response};

	print STDERR "eprint $eprintid, checking $url\n" if $verbose;
    
    # check whether URL has already been processed (avoid duplicate requests)
    if (defined $report->{url}->{$url})
    {
    	$response->{url_message} = "processed";
    }
	elsif ($url =~ /^https?:\/\// || $url =~ /^ftp:\/\// )
	{
		# URL has a valid format
		my $request_counter = 1;
		my $success = 0;
		
		# try first with a HEAD request
		my $req = HTTP::Request->new("HEAD",$url);
		$req->header( "User-Agent" => $useragent_name );
		
		while (!$success && $request_counter <= $crawl_retry)
		{
			print STDERR "Request #$request_counter\n" if ($noise >= 3);
			my $ua = LWP::UserAgent->new;
			$ua->env_proxy;
			$ua->timeout($timeout);
			$response = $ua->request($req);
			$success = $response->is_success;
			my $status_code = $response->code;
			if ( $status_code == HTTP_METHOD_NOT_ALLOWED )
			{
				# HEAD request my not be allowed by the server, try with a GET request
				$req = HTTP::Request->new("GET",$url);
				$req->header( "User-Agent" => $useragent_name );
			}
			$request_counter++;
			sleep $crawl_delay if (!$success && $request_counter <= $crawl_retry);
		}
	}
	else
	{
		# URL has an invalid format
		$response->{url_message} = "invalid";
	}
	
	print STDERR Dumper($response) if $dump_response;
	
	return $response;
}

#
# Process the response and store it in a report hash.
#
sub _evaluate_response
{
	my ( $self, $response, $url, $fieldname ) = @_;
	
	my $eprint = $self->{eprint};
	my $eprintid = $eprint->id;
	
	my $param = $self->{param};
	my $report = $param->{report};
	
	if ( defined $response->{url_message} )
	{
		if ( $response->{url_message} eq 'invalid' )
		{
			$report->{$eprintid}->{$fieldname}->{$url}->{valid} = 0;
			$report->{url}->{$url}->{valid} = 0;
			$report->{invalid_urls}->{$url} = $eprintid;
		}
		
		if ( $response->{url_message} eq 'processed' )
		{
			my $eprintid_processed = $report->{url}->{$url}->{eprintids}[0];
			$report->{$eprintid}->{$fieldname}->{$url}->{valid} = $report->{url}->{$url}->{valid};
			$report->{$eprintid}->{$fieldname}->{$url}->{status} = $report->{$eprintid_processed}->{$fieldname}->{$url}->{status};
			push @{$report->{url}->{$url}->{eprintids}}, $eprintid; 
		}
	}
	else
	{ 
		my $status_code = $response->code;
		my $message = $response->message;
		
		$report->{status_codes}->{$status_code} = 1;
	
		$report->{$eprintid}->{$fieldname}->{$url}->{valid} = 1;
		$report->{$eprintid}->{$fieldname}->{$url}->{status} = $status_code;
		
		$report->{url}->{$url}->{status} = $status_code;
		$report->{url}->{$url}->{message} = $message;
		$report->{url}->{$url}->{valid} = 1;
		push @{$report->{url}->{$url}->{eprintids}}, $eprintid; 
		
		push @{$report->{status}->{$status_code}->{eprintid}->{$eprintid}->{url}}, $url;
		push @{$report->{status}->{$status_code}->{url}->{$url}->{eprintid}}, $eprintid;
	}
	
	return;
}

#
# Set first existing reported issues to resolved.
# 
sub _resolve_issues
{
	my ( $self ) = @_;
	
	my $eprint = $self->{eprint};
	
	if ($eprint->is_set( "item_issues") )
	{
		my $item_issues = $eprint->value( "item_issues" );
		
		my $commit_flag = 0;
		foreach my $issue (@{$item_issues})
		{
			my $issue_id = $issue->{id};
			my $issue_status= $issue->{status};
			
			if ($issue_id =~ /check_url_status|invalid_url/ && $issue_status eq 'reported' ) 
			{
				$issue->{status} = "resolved";
				$commit_flag = 1;
			}
		}
		
		if ($commit_flag)
		{
			$eprint->set_item_issues( $item_issues );
			$eprint->commit;
		}
	}
	
	return;
}


#
# Update the eprint issues table
#
sub _update_issues
{
	my ($self, $response, $url, $fieldname, $pos ) = @_;
	
	my $eprint = $self->{eprint};
	my $eprintid = $eprint->id;
	
	my $param = $self->{param};
	my $report = $param->{report};
	
	my @issues = ();
	my $issue = {};

	if ( defined $response->{url_message} )
	{
		if ( $response->{url_message} eq 'invalid' )
		{
			$issue = $self->_update_issue_invalid_url( $url, $fieldname, $pos );
			push @issues, $issue;
		}
		
		if ( $response->{url_message} eq 'processed' )
		{
			my $eprintid_processed = $report->{url}->{$url}->{eprintids}[0];
			
			if ($report->{$eprintid_processed}->{$fieldname}->{$url}->{valid} == 0)
			{
				$issue = $self->_update_issue_invalid_url( $url, $fieldname, $pos );
				push @issues, $issue;
			}
			else 
			{
				my $status_code = $report->{url}->{$url}->{status};
				my $message = $report->{url}->{$url}->{message};
				if ($status_code != HTTP_OK)
				{
					$issue = $self->_update_issue_url_status( $url, $fieldname, $pos, $status_code, $message );
					push @issues, $issue;
				}
			}
		}
	}
	else
	{ 
		my $status_code = $response->code;
		my $message = $response->message;
		
		if ($status_code != HTTP_OK)
		{
			$issue = $self->_update_issue_url_status( $url, $fieldname, $pos, $status_code, $message );
			push @issues, $issue;
		}
	}
	
	$eprint->set_item_issues( \@issues ) if scalar(@issues);
	$eprint->commit;
	
	return;
}

#
# Create an eprint issues entry for an invalid URL.
#
sub _update_issue_invalid_url
{
	my ( $self, $url, $fieldname, $pos ) = @_;
	
	my $session = $self->{session};
	
	my $eprint = $self->{eprint};
	my $eprintid = $eprint->id;
	
	my $issue = {};
	
	$issue->{id} = "invalid_url_" . $fieldname ."_" . $pos . "_" . $eprintid;
	$issue->{type} = "invalid_url";
	$issue->{status} = "reported";
			
	my $desc = $session->make_doc_fragment;
	$desc->appendChild( $session->make_text( "Invalid URL (" . $fieldname . "):" ) );
	$desc->appendChild( $session->make_element( "br" ) );
	$desc->appendChild( $session->make_text( $url ) );
	$issue->{description} = $desc;
	
	return $issue;
}

#
# Create an eprint issues entry for a malfunctioning URL (HTTP status != 200 )
#
sub _update_issue_url_status
{
	my ( $self, $url, $fieldname, $pos, $status_code, $message ) = @_;
	
	my $session = $self->{session};
	my $eprint = $self->{eprint};
	my $eprintid = $eprint->id;
	
	my $issue = {};
	
	$issue->{id} = "check_url_status_" . $fieldname ."_" . $pos . "_" . $eprintid;;
	$issue->{type} = "check_url_status";
	$issue->{status} = "reported";
			
	my $desc = $session->make_doc_fragment;
	$desc->appendChild( $session->make_text( "Check URL (" . $fieldname . "):" ) );
	$desc->appendChild( $session->make_element( "br" ) );
	my $url_link = $session->make_element( "a",
		href => $url,
		target => '_blank'
	);
	$url_link->appendChild( $session->make_text( $url ) );
	$desc->appendChild( $url_link );
	$desc->appendChild( $session->make_element( "br" ) );
	$desc->appendChild( $session->make_text( "HTTP Status Code " . $status_code . ", " . $message ) );
	$issue->{description} = $desc;
	
	return $issue;
}

#
# In multiple URL fields, fix URLs that have an empty url value, but still the 
# other keys set.
#
sub _fix_urls
{
	my ($self, $fieldname) = @_;
	
	my $eprint = $self->{eprint};
	
	my $urls = $eprint->get_value( $fieldname ); 
	
	foreach my $url_record (@{$urls})
	{
		next if (defined $url_record->{url});
		
		foreach my $key (keys %{$url_record})
		{
			$url_record->{$key} = '';
		}
	}
	
	$eprint->set_value( $fieldname, $urls );
	$eprint->commit;
	
	return;
}

#
# Print a report of all checked URLs. 
#
sub print_report
{
	my ($self) = @_;
	
	my $param = $self->{param};
	my $report = $param->{report};
	
	print STDOUT "URL Status Report\n";
	print STDOUT "=================\n\n";
	
	if ( scalar($report->{invalid_urls}) )
	{
		print STDOUT "Invalid URLs\n";
		print STDOUT "------------\n";
	
		foreach my $url (keys %{$report->{invalid_urls}})
		{
			my $eprintid = $report->{invalid_urls}->{$url};
			print STDOUT "eprint $eprintid, url $url\n";
		}
		
		print STDOUT "\n";
	}
	
	print STDOUT "Report by HTTP Status Code, eprintid\n";
	print STDOUT "------------------------------------\n";
	
	my $eprint_total_count = 0;
	my $url_total_count = 0;
	my $url_ok_count = 0;
	my $url_failed_count = 0;
	
	foreach my $status_code (sort keys %{$report->{status_codes}})
	{
		my $message = status_message($status_code);
		print STDOUT "HTTP Status Code $status_code, $message:\n";
		
		my $url_count = 0;
		my $eprint_count = 0;
		foreach my $eprintid (sort {$a <=> $b} keys %{$report->{status}->{$status_code}->{eprintid}})
		{
			$eprint_count++;
			$eprint_total_count++;
			foreach my $url (@{$report->{status}->{$status_code}->{eprintid}->{$eprintid}->{url}})
			{
				print STDOUT "eprint $eprintid, url $url\n";
				$url_count++;
				$url_total_count++;
				$url_ok_count++ if ($status_code == 200);
				$url_failed_count++ if ($status_code != 200);
			}
		}
		
		print STDOUT "$eprint_count eprints, $url_count URLs checked\n";
		print STDOUT "\n";
	}
	
	print STDOUT "Summary: Checked $eprint_total_count eprints, $url_total_count URLs: $url_ok_count OK, $url_failed_count failed.\n\n";
	
	print STDOUT "Report by HTTP Status Code, URL\n";
	print STDOUT "-------------------------------\n";
	
	foreach my $status_code (sort keys %{$report->{status_codes}})
	{
		my $message = status_message($status_code);
		print STDOUT "HTTP Status Code $status_code, $message:\n";
		
		foreach my $url (sort keys %{$report->{status}->{$status_code}->{url}})
		{
			foreach my $eprintid (@{$report->{status}->{$status_code}->{url}->{$url}->{eprintid}})
			{
				print STDOUT "url $url, eprint $eprintid\n";
			}
		}
		print STDOUT "\n";
	}
	
	return;
}

1;

=head1 AUTHOR

Martin Braendle <martin.braendle@id.uzh.ch>, Zentrale Informatik, University of Zurich

=head1 COPYRIGHT

=for COPYRIGHT BEGIN

Copyright 2017- University of Zurich.

=for COPYRIGHT END

=for LICENSE BEGIN

This file is of the LinkCheck package based on EPrints L<http://www.eprints.org/>.

EPrints is free software: you can redistribute it and/or modify it
under the terms of the GNU Lesser General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

EPrints is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
License for more details.

You should have received a copy of the GNU Lesser General Public
License along with EPrints.  If not, see L<http://www.gnu.org/licenses/>.

=for LICENSE END