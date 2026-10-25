<?php
// P5-07: PBX features through the FreePBX 17 API, for extension 1002 (the
// sipp UAS) and 1003 (never registered):
//   php features.php     (ringgroups installed before: "fwconsole ma install ringgroups")
// - conference 8000 (ConfBridge);
// - queue 7000, static member 1002;
// - ring group 6000 (ringall, 1002);
// - IVR test-ivr: DTMF 2 -> extension 1002; misc application 7100 -> IVR;
// - time conditions on time groups with the time forced: tc-true (time group
//   "always") -> 1002, else congestion; tc-false (a month other than the
//   current one) -> 1002, else congestion; misc applications 7201 / 7202.
// Then "fwconsole reload".
include '/etc/freepbx.conf';
$ext1002 = 'from-did-direct,1002,1';
$busy = 'app-blackhole,congestion,1';

conferences_add('8000', 'test-conf', '', '', '');
echo "conference 8000\n";
// queues_add reads the queue options from $_REQUEST (the web form): the
// defaults of the form
$_REQUEST += ['announcefreq' => 0, 'announceholdtime' => 'no', 'announcemenu' => 'none', 'announceposition' => 'no',
    'answered_elsewhere' => '0', 'autofill' => 'no', 'autopause' => 'no', 'autopausebusy' => 'no', 'autopausedelay' => 0,
    'autopauseunavail' => 'no', 'breakouttype' => 'announcement', 'callback' => 'none', 'eventmemberstatus' => 'no',
    'eventwhencalled' => 'no', 'joinempty' => 'yes', 'leavewhenempty' => 'no', 'maxlen' => 0, 'memberdelay' => 0,
    'min-announce' => 15, 'music' => 'default', 'pannouncefreq' => 0, 'penaltymemberslimit' => 0, 'recording' => 'dontcare',
    'reportholdtime' => 'no', 'retry' => 5, 'rtone' => 0, 'rvol_mode' => '', 'rvolume' => '', 'servicelevel' => 60,
    'skip_joinannounce' => '', 'strategy' => 'ringall', 'timeout' => 15, 'timeoutpriority' => 'app',
    'timeoutrestart' => 'no', 'weight' => 0, 'wrapuptime' => 0];
// dynmembers (15th) must be an array: its default '' breaks array_unique()
queues_add('7000', 'test-queue', '', '', 'app-blackhole,hangup,1', 0, ['Local/1002@from-queue/n,0'], 0, 30, '', '0', '', '0', '0', []);
echo "queue 7000\n";
ringgroups_add('6000', 'ringall', '20', '1002', 'app-blackhole,hangup,1', 'test-rg');
echo "ring group 6000\n";

$ivr = FreePBX::Ivr();
$ivr->saveDetails(['id' => '', 'name' => 'test-ivr', 'description' => 'P5-07', 'announcement' => null,
    'directdial' => '', 'invalid_loops' => '3', 'invalid_retry_recording' => 'default', 'invalid_destination' => '',
    'timeout_enabled' => '', 'invalid_recording' => 'default', 'retvm' => '', 'timeout_time' => 10,
    'timeout_recording' => 'default', 'timeout_retry_recording' => 'default', 'timeout_destination' => '',
    'timeout_loops' => '3', 'timeout_append_announce' => 1, 'invalid_append_announce' => 1, 'timeout_ivr_ret' => 0,
    'invalid_ivr_ret' => 0, 'alertinfo' => '', 'rvolume' => '', 'strict_dial_timeout' => 2, 'accept_pound_key' => 0]);
$ivrid = FreePBX::Database()->query("SELECT id FROM ivr_details WHERE name = 'test-ivr'")->fetchColumn();
$ivr->saveEntries($ivrid, ['ext' => ['2'], 'goto' => [$ext1002], 'ivr_ret' => [0]]);
miscapps_add('test-ivr', '7100', "ivr-$ivrid,s,1");
echo "ivr $ivrid, misc application 7100\n";

$other = strtolower(date('M', strtotime('first day of +2 months')));
$tc = FreePBX::Timeconditions();
foreach (['tc-true' => ['00:00-23:59|*|*|*', '7201'], 'tc-false' => ["00:00-23:59|*|*|$other", '7202']] as $name => [$times, $code]) {
    $tg = timeconditions_timegroups_add_group_timestrings("tg-$name", [$times]);
    $id = $tc->addTimeCondition(['displayname' => $name, 'time' => $tg, 'invert_hint' => '0', 'timezone' => 'default',
        'goto0' => 'g', 'g0' => $ext1002, 'goto1' => 'g', 'g1' => $busy, 'mode' => 'time-group']);
    miscapps_add($name, $code, "timeconditions,$id,1");
    echo "$name: time group $tg ($times), time condition $id, misc application $code\n";
}
needreload();
