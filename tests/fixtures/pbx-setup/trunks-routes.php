<?php
// P5-02: PBX configuration through the FreePBX 17 API (the same calls as the
// web UI; fwconsole bulkimport only knows extensions and DIDs):
//   php trunks-routes.php REG_PROVIDER_IP IP_PROVIDER_IP
// - trunk prov-reg: PJSIP, registration "send" with username/secret to
//   REG_PROVIDER_IP; trunk prov-ip: PJSIP, no registration nor auth,
//   identified by IP_PROVIDER_IP (match);
// - outbound route test-out: prefix 9 removed, 0XXXXXX to prov-reg;
// - IVR test-ivr (option 1 -> extension 1001); inbound route DID 5551234
//   -> test-ivr.
// Then "fwconsole reload".
include '/etc/freepbx.conf';
[$_, $regip, $ipip] = $argv;
$trunk = function ($name, $settings) {
    $_POST['imports'] = $settings + ['trunk_name' => $name, 'channelid' => $name, 'sip_server_port' => '5060',
        'context' => 'from-pstn', 'qualify_frequency' => '0'];
    $id = FreePBX::Core()->addTrunk($name, 'pjsip', []);
    echo "trunk $name: $id\n";
    return $id;
};
$reg = $trunk('prov-reg', ['sip_server' => $regip, 'authentication' => 'outbound', 'registration' => 'send',
    'username' => 'izpbxtrunk', 'auth_username' => 'izpbxtrunk', 'secret' => 'TrunkSecret1']);
$trunk('prov-ip', ['sip_server' => $ipip, 'authentication' => 'none', 'registration' => 'none', 'match' => $ipip]);

$routing = new FreePBX\modules\Core\Components\Outboundrouting();
$route = $routing->add('test-out', '', '', '', '', '', 'default', '',
    [['prepend_digits' => '', 'match_pattern_prefix' => '9', 'match_pattern_pass' => '0XXXXXX', 'match_cid' => '']],
    [$reg]);
echo "outbound route test-out: $route\n";

$ivr = FreePBX::Ivr();
$ivr->saveDetails(['id' => '', 'name' => 'test-ivr', 'description' => 'P5-02', 'announcement' => null,
    'directdial' => '', 'invalid_loops' => '3', 'invalid_retry_recording' => 'default', 'invalid_destination' => '',
    'timeout_enabled' => '', 'invalid_recording' => 'default', 'retvm' => '', 'timeout_time' => 10,
    'timeout_recording' => 'default', 'timeout_retry_recording' => 'default', 'timeout_destination' => '',
    'timeout_loops' => '3', 'timeout_append_announce' => 1, 'invalid_append_announce' => 1, 'timeout_ivr_ret' => 0,
    'invalid_ivr_ret' => 0, 'alertinfo' => '', 'rvolume' => '', 'strict_dial_timeout' => 2, 'accept_pound_key' => 0]);
$ivrid = FreePBX::Database()->query("SELECT id FROM ivr_details WHERE name = 'test-ivr'")->fetchColumn();
$ivr->saveEntries($ivrid, ['ext' => ['1'], 'goto' => ['from-did-direct,1001,1'], 'ivr_ret' => [0]]);
echo "ivr test-ivr: $ivrid\n";

$did = ['extension' => '5551234', 'cidnum' => '', 'description' => 'P5-02', 'destination' => "ivr-$ivrid,s,1"];
FreePBX::Core()->addDIDDefaults($did);
FreePBX::Core()->addDID($did);
echo "inbound route 5551234: ivr-$ivrid\n";
needreload();
