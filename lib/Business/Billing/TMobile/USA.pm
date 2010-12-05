package TMobileAccount;

use strict;
use warnings;
use LWP;
use YAML;
use Data::Dumper;

use constant {
   LOGIN_URL     => 'https://my.t-mobile.com/Login/MyTMobileLogin.aspx',
   REFILL_URL    => 'https://my.t-mobile.com/account/refilloverview.aspx',
   DEBUG_OUT_FMT => '/tmp/out_%s.html',
};
my @mytmo_fields = qw(user full_name first_name is_prepaid);
my $mytmo_regex  = qr/Msisdn=(.*)&SubscriberName=(.*)&FirstName=(.*)&IsPrePaidSubscriber=(.*?)&/;
my %field_map = qw(
    acctBalance_lblPhoneNumber            phone_number
    acctBalance_lblRatePlanName           rate_plan_name
    acctBalance_lblMinutes                minutes 
    acctBalance_lblMessages               messages
    acctBalance_lblPrePaidBalancePlan     balance
    acctBalance_lblNextPlanChangeToRemove next_charge
    );

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
    }else {
        # Initialize the cookies if none
        $self->{browser}->cookie_jar
            or $self->{browser}->cookie_jar({}); 
    }
    bless($self, $class);
}

sub login {
    my $self = shift;
    my %p = (user     => undef,
             password => undef,
             @_);

    $p{user} and $p{password}
        or die "Need a user and passwd for login()";

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
            'Login1:txtMSISDN'   => $p{user},
            'Login1:txtPassword' => $p{password},
            'Login1:txtLoginPage' => 'MyTMobileLogin.aspx',
            '__EVENTVALIDATION'  => $event_id,
            '__EVENTTARGET'      => 'Login1$btnLogin',
        });

    $self->{debug}
        and $self->write_debug_file(text => $result->content, name => 'LOGIN_POST');

    my $mytmobile = $self->{browser}->cookie_jar->{COOKIES}->{'.t-mobile.com'}->{'/'}->{MyTMobile}
        or return undef;

    $self->{debug}
        and printf "Login sucess %s\n", $mytmobile->[1];

    # There is some account info int he cookies
    my %account_info;
    if (my @matches = $mytmobile->[1] =~ /$mytmo_regex/) {
        @account_info{@mytmo_fields} = @matches;
    }
    $self->{debug}
        and print YAML::Dump(\%account_info);

    return \%account_info;
}
sub get_prepay_details {
    my $self = shift;

    my $result = $self->{browser}->get(REFILL_URL);

    $self->{debug}
        and $self->write_debug_file(text => $result->content, name  => 'REFILL_GET');

    my %account_info = ();
    while (my ($label, $key) = each %field_map) {
        if ($result->content =~ /"$label">(.*?)</) {
            $account_info{$key} = $1;
        }
    }
    $self->{debug}
        and printf "Got prepay data: \n%s\n", YAML::Dump(\%account_info);

    return %account_info;
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

package main;
my ($user, $password) = @ARGV;

$user and $password
    or die "Need a user and password";

print YAML::Dump($user, $password);

my $account =  TMobileAccount->new(debug =>1);

my $data = $account->login(user => $user, password => $password)
    or die "Problem logging in";

$data->{is_prepaid} =~ /false/i
    and die "Not a prepay account";

my $prepay_info = $account->get_prepay_details();

