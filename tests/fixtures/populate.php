<?php
// Populate a FreePBX 16 install with the T5 fixture content (DB part).
// Run inside the izPBX container as asterisk: php populate.php
// Files (voicemail messages, audio, astdb, dongle.conf) are handled by populate.sh.

$bootstrap_settings['freepbx_auth'] = false;
include '/etc/freepbx.conf';

$pdo = FreePBX::Database();
$core = FreePBX::Core();

function step($msg) { fwrite(STDERR, "populate: $msg\n"); }

// --- trunks
step('chan_sip trunk with IP auth (provider sends to port 5160)');
$core->addTrunk('prov-sip-ip', 'sip', [
  'channelid' => 'prov-sip-ip',
  'peerdetails' => "type=peer\nhost=192.0.2.10\nport=5060\ninsecure=port,invite\ncontext=from-trunk\ndisallow=all\nallow=alaw&ulaw\nqualify=no\ndtmfmode=rfc2833",
  'usercontext' => '', 'userconfig' => '', 'register' => '',
  'maxchans' => '', 'outcid' => '', 'keepcid' => 'off', 'failtrunk' => '',
  'disabletrunk' => 'off', 'dialoutprefix' => '', 'provider' => '', 'continue' => 'off',
]);

step('pjsip trunk with outbound registration');
$core->addTrunk('prov-pjsip-reg', 'pjsip', [
  'channelid' => 'prov-pjsip-reg',
  'trunk_name' => 'prov-pjsip-reg', 'auth_username' => '', 'sendrpid' => 'no',
  'rtp_symmetric' => 'yes', 'rewrite_contact' => 'yes', 'force_rport' => 'yes',
  'direct_media' => 'no', 'fax_detect' => 'no', 'inband_progress' => 'no',
  'send_connected_line' => 'false', 'support_path' => 'no', 'language' => '', 'match' => '',
  'from_user' => '', 'from_domain' => '', 'contact_user' => '', 'client_uri' => '',
  'server_uri' => '', 'aor_contact' => '', 'outbound_proxy' => '',
  'username' => 'fixtureuser', 'secret' => 'Fx-trunk-reg-pw', 'authentication' => 'outbound',
  'registration' => 'send', 'sip_server' => '192.0.2.20', 'sip_server_port' => '5060',
  'context' => 'from-pstn', 'transport' => '0.0.0.0-udp', 'dtmfmode' => 'rfc4733',
  'expiration' => '3600', 'retry_interval' => '60', 'max_retries' => '10',
  'forbidden_retry_interval' => '10', 'fatal_retry_interval' => '0',
  'auth_rejection_permanent' => 'off', 'qualify_frequency' => '60',
  'maxchans' => '', 'outcid' => '', 'keepcid' => 'off', 'failtrunk' => '',
  'disabletrunk' => 'off', 'dialoutprefix' => '', 'provider' => '', 'continue' => 'off',
]);

$trunks = [];
foreach ($core->listTrunks() as $t) { $trunks[$t['name']] = $t['trunkid']; }

// --- outbound route via both trunks
step('outbound route');
core_routing_addbyid('fixture-out', '', '', '', '', '', 'default', '', [
  ['match_pattern_prefix' => '', 'match_pattern_pass' => '0.', 'match_cid' => '', 'prepend_digits' => ''],
], [$trunks['prov-pjsip-reg'], $trunks['prov-sip-ip']]);

// --- custom system recording (the audio file is created by populate.sh)
step('system recording');
$pdo->prepare("INSERT INTO recordings (displayname, filename, description, fcode, fcode_pass, fcode_lang) VALUES (?, ?, ?, 0, '', '')")
   ->execute(['fixture-welcome', 'custom/fixture-welcome', 'fixture custom prompt']);
$rec_id = $pdo->lastInsertId();

// --- custom MoH category (files created by populate.sh)
step('music on hold category');
$pdo->prepare("INSERT INTO music (category, type, random, application, format) VALUES ('fixture-moh', 'files', 0, '', '')")->execute();

// --- ring group 600 (1002, 1003)
step('ring group 600');
ringgroups_add('600', 'ringall', 20, '1002-1003', 'app-blackhole,hangup,1', 'Fixture RG', '', '0', '', '', '0', '0', 'Ring', '', '', 'default', '', '', 'dontcare', 'yes', '', '');

// --- queue 700 (static members 1002, 1003)
step('queue 700');
queues_add('700', 'Fixture Queue', '', '', 'app-blackhole,hangup,1', '0', ['Local/1002@from-queue/n,0', 'Local/1003@from-queue/n,0'], '0', '', '', '0', '', '0', '0', []);

// --- IVR: 1 -> ext 1002, 2 -> queue 700, 3 -> ring group 600
step('IVR');
$ivr = FreePBX::Ivr();
$ivr_id = $ivr->saveDetails([
  'id' => '', 'name' => 'Fixture IVR', 'description' => 'fixture main menu',
  'announcement' => $rec_id, 'directdial' => 'ext-local', 'invalid_loops' => '3',
  'invalid_retry_recording' => 'default', 'invalid_destination' => 'app-blackhole,hangup,1',
  'timeout_enabled' => '', 'invalid_recording' => 'default', 'retvm' => '', 'timeout_time' => '10',
  'timeout_recording' => 'default', 'timeout_retry_recording' => 'default',
  'timeout_destination' => 'app-blackhole,hangup,1', 'timeout_loops' => '3',
  'timeout_append_announce' => '1', 'invalid_append_announce' => '1',
  'timeout_ivr_ret' => '0', 'invalid_ivr_ret' => '0', 'alertinfo' => '', 'rvolume' => '',
  'strict_dial_timeout' => '2', 'accept_pound_key' => '0',
]);
$ivr->saveEntries($ivr_id, [
  'ext' => ['1', '2', '3'],
  'goto' => ['from-did-direct,1002,1', 'ext-queues,700,1', 'ext-group,600,1'],
  'ivr_ret' => ['0', '0', '0'],
]);

// --- time group + time condition: office hours -> IVR, otherwise voicemail of 1001
step('time condition');
$tg = timeconditions_timegroups_add_group_timestrings('Fixture office hours', ['09:00-18:00|mon-fri|*|*']);
$pdo->prepare("INSERT INTO timeconditions (displayname, time, truegoto, falsegoto, deptname, generate_hint, invert_hint, fcc_password, priority, timezone, mode) VALUES (?, ?, ?, ?, '', '1', '0', '', '0', 'Europe/Rome', 'time-group')")
   ->execute(['Fixture office hours', $tg, "ivr-$ivr_id,s,1", 'ext-local,vmu1001,1']);
$tc_id = $pdo->lastInsertId();

// --- inbound routes: main DID -> time condition, fax DID with fax detection
step('inbound routes and fax');
$core->addDID(['extension' => '0612345678', 'cidnum' => '', 'destination' => "timeconditions,$tc_id,1", 'description' => 'Fixture main DID']);
$core->addDID(['extension' => '0612345679', 'cidnum' => '', 'destination' => 'from-did-direct,1003,1', 'description' => 'Fixture fax DID']);
$pdo->prepare("INSERT INTO fax_incoming (cidnum, extension, detection, detectionwait, destination, legacy_email, ring) VALUES ('', '0612345679', 'spandsp', '4', 'from-did-direct,1003,1', NULL, 0)")->execute();

// --- userman / UCP users, one per extension; fax to email on 1003
step('userman users');
$um = FreePBX::Userman();
$uid = [];
foreach (['1001' => 'Fixture SIP One', '1002' => 'Fixture PJSIP Two', '1003' => 'Fixture PJSIP Three'] as $ext => $name) {
  $r = $um->addUser("u$ext", "Fx-ucp-$ext-pw", $ext, $name, ['displayname' => $name, 'email' => "u$ext@example.invalid"]);
  if (empty($r['status'])) { fwrite(STDERR, "populate: addUser u$ext failed: " . json_encode($r) . "\n"); exit(1); }
  $uid[$ext] = $r['id'];
}
$pdo->prepare("REPLACE INTO fax_users (user, faxenabled, faxemail, faxattachformat) VALUES (?, 'true', 'fax@example.invalid', 'pdf')")
   ->execute([$uid['1003']]);

needreload();
step('done');
