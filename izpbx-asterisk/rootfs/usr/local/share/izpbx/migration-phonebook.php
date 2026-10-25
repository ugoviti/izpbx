<?php
// izPBX migration, D28 and D30: the phonebook and the system speed dials of
// FreePBX 16 (astdb cidname/<number> = name, sysspeeddials/<code> = number)
// into a Contact Manager group of FreePBX 17, a speed dial keeping its code;
// every entry also in a CSV. The personal speed dials of the speeddial module
// (AMPUSER/<ext>/speeddials/<code>) have no equivalent: written to USERS.csv.
//   php migration-phonebook.php ASTDB.sqlite3 OUT.csv GROUP USERS.csv
// Prints "<entries> <speed dials> <personal speed dials>". Run as asterisk,
// Asterisk running.
include '/etc/freepbx.conf';
[$astdb, $csv, $group, $userscsv] = array_slice($argv, 1);
$names = [];
$speeddials = [];
$personal = [];
foreach ((new PDO('sqlite:' . $astdb))->query('SELECT key, value FROM astdb') as $r) {
  if (preg_match('#^/cidname/(.+)$#', $r[0], $m)) $names[$m[1]] = $r[1];
  if (preg_match('#^/sysspeeddials/(.+)$#', $r[0], $m)) $speeddials[$m[1]] = $r[1];
  if (preg_match('#^/AMPUSER/([^/]+)/speeddials/(.+)$#', $r[0], $m)) $personal[] = [$m[1], $m[2], $r[1]];
}
$f = fopen($userscsv, 'w');
fputcsv($f, ['extension', 'speeddial', 'number']);
foreach ($personal as $p) fputcsv($f, $p);
fclose($f);
// a speed dial to a number with no name: the number is the name
foreach ($speeddials as $number) {
  if (!isset($names[$number])) $names[$number] = $number;
}
$cm = FreePBX::Contactmanager();
$g = $cm->addGroup($group, 'external', -1, false);
if (empty($g['id'])) {
  fwrite(STDERR, "cannot create the Contact Manager group '$group': " . ($g['message'] ?? '?') . "\n");
  exit(1);
}
$f = fopen($csv, 'w');
fputcsv($f, ['number', 'name', 'speeddial']);
foreach ($names as $number => $name) {
  // PHP turns numeric array keys ("1003") into integers
  $number = (string)$number;
  $code = array_search($number, $speeddials, true);
  fputcsv($f, [$number, $name, $code === false ? '' : $code]);
  $num = ['number' => $number, 'type' => 'other', 'locale' => ''];
  if ($code !== false) $num['speeddial'] = (string)$code;
  $cm->addEntryByGroupID($g['id'], ['displayname' => $name, 'fname' => $name, 'numbers' => [$num]], false);
}
fclose($f);
echo count($names), ' ', count($speeddials), ' ', count($personal), "\n";
