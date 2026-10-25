<?php
// P5-11: an administrator (admin / AdminPass1, all sections) and a UCP user
// (ucpuser / UcpPass1, UCP login allowed) through the FreePBX 17 API, and the
// misc application 7300 -> music on hold (app-blackhole,musiconhold).
// Then "fwconsole reload".
include '/etc/freepbx.conf';
FreePBX::Core()->addAMPUser('admin', 'AdminPass1', '', '', '', ['*']);
$u = FreePBX::Userman();
$r = $u->addUser('ucpuser', 'UcpPass1', 'none', 'P5-11');
// created through the API the user is in no group: UCP login set on the user
$u->setModuleSettingByID($r['id'], 'ucp|Global', 'allowLogin', true);
miscapps_add('test-moh', '7300', 'app-blackhole,musiconhold,1');
needreload();
echo "admin, ucpuser ({$r['id']}), misc application 7300\n";
