use Business::Billing::TMobile::USA;
use YAML;

my ($user, $password) = @ARGV;

$user and $password
    or die "Need a user and password";

print YAML::Dump($user, $password);

my $account = Business::Billing::TMobile::USA->new(debug =>1);

my $data = $account->login(user => $user, password => $password)
    or die "Problem logging in";

$data->{is_prepaid} =~ /false/i
    and die "Not a prepay account";

my $prepay_info = $account->get_prepay_details();
