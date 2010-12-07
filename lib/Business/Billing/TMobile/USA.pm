package Business::Billing::TMobile::USA;
use vars qw($VERSION);
$VERSION = '0.02';

use strict;
use warnings;
use LWP;
use YAML;
use Data::Dumper;

use constant {
   LOGIN_URL     => 'https://my.t-mobile.com/Login/MyTMobileLogin.aspx',
   ACCOUNT_URL   => 'https://my.t-mobile.com/account',
   REFILL_URL    => 'https://my.t-mobile.com/account/refilloverview.aspx',

   DEBUG_OUT_FMT => '/tmp/out_%s.html',
};

my @mytmo_fields = qw(user full_name first_name is_prepaid);
my $mytmo_regex  = qr/Msisdn=(.*)&SubscriberName=(.*)&FirstName=(.*)&IsPrePaidSubscriber=(.*?)&/;

my %account_field_map = qw(
    );

my %refill_field_map = qw(
    ucAccountBalance_lblUseBy             expiration
    acctBalance_lblPhoneNumber            phone_number
    acctBalance_lblRatePlanName           rate_plan_name
    acctBalance_lblMinutes                minutes 
    acctBalance_lblMessages               messages
    acctBalance_lblPrePaidBalancePlan     balance
    acctBalance_lblNextPlanChangeToRemove next_charge
    );

=head2 METHODS

=cut

=item new

=cut

sub new {
    my $class = shift;
    my %p     = (debug => 0,
                 browser => undef,
                 cookies => undef,
                 @_);

    my $self = \%p;

    # Get new browser if we don't have one
    defined $self->{browser}
        or $self->{browser} = LWP::UserAgent->new;

    if ($p{cookies}) {
        $self->{browser}->cookie_jar($p{cookies});
    } else {
        # Initialize the cookies if none
        my $cookie_jar = {};
        if ($self->{debug}) {
             require HTTP::Cookies;
             $cookie_jar = HTTP::Cookies->new(
                 ignore_discard => 1,
                 autosave => 1,
             );
        }
        $self->{browser}->cookie_jar
            or $self->{browser}->cookie_jar($cookie_jar); 
    }
    bless($self, $class);
}

=item login(username => string, password =>string)

I<username> : The username of the tmobile user this is usually your 10-digit
phone number

I<password> : Plain text password

Returns reference to hash of account info on success, dies on error

Result hash will contain the following:

  first_name: John
  full_name:  John+Smith
  is_prepaid: True
  user:       8475551212

=cut

sub login {
    my $self = shift;
    my %p = (username => undef,
             password => undef,
             @_);

    $p{username} and $p{password}
        or die "Need a username and passwd for login()";

    my $result = $self->{browser}->get(LOGIN_URL);

    my $event_regex = qr/id="__EVENTVALIDATION" value="(.*?)"/;

    my $event_id;
    if ($result->content =~ /$event_regex/) {
        $event_id = $1;
    }

    $event_id
        or die "Unable to determine event code";

    $self->{debug}
        and printf "Got event validation code = %s\n", $event_id;

    $result = $self->{browser}->post(LOGIN_URL,
        {
            'Login1:txtMSISDN'   => $p{username},
            'Login1:txtPassword' => $p{password},
            'Login1:txtLoginPage' => 'MyTMobileLogin.aspx',
            '__EVENTVALIDATION'  => $event_id,
            '__EVENTTARGET'      => 'Login1$btnLogin',
        });

    $self->{debug}
        and $self->write_debug_file(text => $result->content, name => 'LOGIN_POST');
    $self->{debug}
        and $self->{browser}->cookie_jar->save('/tmp/tmo_login_cookies.dat');

    my $account_info = _parse_login_cookies(cookie_jar => $self->{browser}->cookie_jar);
    $self->{debug}
        and print YAML::Dump($account_info);

    return $account_info;
    

}

sub _parse_login_cookies {
    my %p    = ( cookie_jar => undef,
                 @_);

    unless ($p{cookie_jar} and $p{cookie_jar}->isa("HTTP::Cookies")) {
        warn "No cookies supplied to parse";
        return undef
    }

    my $mytmobile = $p{cookie_jar}->{COOKIES}->{'.t-mobile.com'}->{'/'}->{MyTMobile}
        or return undef;

    # There is some account info in the cookies
    my %account_info;
    if (my @matches = $mytmobile->[1] =~ /$mytmo_regex/) {
        @account_info{@mytmo_fields} = @matches;
    }


    return \%account_info;
}

=item get_prepay_details()

Attempts to fetch the refill details page and the accounts page to collect
prepaid balace and expiration data.

Returns reference to a hash of account data.  Dies on error.

Result hash will contain the following:

    balance:        $76.37
    expiration:     6/20/2011 12:00:00 AM
    messages:       1068
    minutes:        746
    next_charge:    N/A
    phone_number:   847-555-1212
    rate_plan_name: Pay As You Go


=cut

sub get_prepay_details {
    my $self = shift;

    my $result = $self->{browser}->get(REFILL_URL);

    $self->{debug}
        and $self->write_debug_file(text => $result->content, name  => 'REFILL_GET');

    my $text = $result->content;

    $result = $self->{browser}->get(ACCOUNT_URL);
    $self->{debug}
        and $self->write_debug_file(text => $result->content, name  => 'ACCOUNT_GET');
    $text .= $result->content;

    my %account_info = _parse_refill_pages( content => $text);

    $self->{debug}
        and printf "Got prepay data: \n%s\n", YAML::Dump(\%account_info);

    return \%account_info;
}

sub _parse_refill_pages {
    my %p = (content => undef,
             @_);

    unless($p{content}) {
        warn("No text supplied to parse");
        return undef;
    }

    my %account_info = ();

    # You might think that parsing the HTML with something like HTML::Tree would be 
    # reasonable, but we can't trust how well formed these crappy pages are.
    while (my ($label, $key) = each %refill_field_map) {
        if ($p{content}=~ /"$label">(.*?)</) {
            $account_info{$key} = $1;
        }
    }

    return \%account_info;
}

sub write_debug_file {
    my $self = shift;
    my %p    = (
        text => "",
        name => undef,
        @_);

    for my $param (qw(text name)) {
        defined $p{$param}
          or die("Missing param %s for debug write", $param);
    }

    my $file_name = sprintf (DEBUG_OUT_FMT, $p{name});

    unless($p{text}) {
        warn "No text to write, skipping file %s", $file_name;
        return undef;
    }

    my $debug_fh;
    open($debug_fh, '>', $file_name)
        or die "Trouble writing";
    print $debug_fh $p{text};
    close $debug_fh;
    printf "Wrote Debug file %s\n", $file_name;
    return 1;
}

