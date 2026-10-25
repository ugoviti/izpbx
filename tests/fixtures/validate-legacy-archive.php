<?php
// Validate a FreePBX "legacy" backup archive with the FreePBX 17 Backup module,
// without restoring it: the steps of Handlers/Restore/Legacy.php before any
// write (type detection, extraction, manifest and astdb, the SQL dump loaded
// into a temporary SQLite database, its tables mapped to the active modules).
//   php validate-legacy-archive.php ARCHIVE OUT.json [TABLE...]
// Writes JSON to OUT.json (the restore handler logs on stdout): type,
// manifest, astdb_families, sql_files, tables, unknown,
// modules (tables mapped per module), rows (row count of each TABLE).
// Exit 1 when the archive is not usable.
include '/etc/freepbx.conf';
$fp = FreePBX::Create();
$file = $argv[1] ?? '';
$json = $argv[2] ?? '';
$want = array_slice($argv, 3);
$fail = function ($msg) { fwrite(STDERR, "invalid archive: $msg\n"); exit(1); };
is_file($file) || $fail("no file $file");

$out = ['type' => $fp->Backup->determineBackupFileType($file)];
$out['type'] === 'legacy' || $fail("type is {$out['type']}, not legacy");

$h = new FreePBX\modules\Backup\Handlers\Restore\Legacy($fp, $file, 'izpbx-validate-' . getmypid(), getmypid());
$call = function ($name, ...$args) use ($h) {
  $m = new ReflectionMethod($h, $name);
  $m->setAccessible(true);
  return $m->invoke($h, ...$args);
};
$prop = function ($name) use ($h) {
  $p = new ReflectionProperty($h, $name);
  $p->setAccessible(true);
  return $p->getValue($h);
};
$call('extractFile');
$call('buildData');   // exits 1 itself on a corrupted manifest
$data = $prop('data');
$tmp = $prop('tmp');
$manifest = $data['manifest'];
empty($manifest['pbx_version']) && $fail('manifest without pbx_version');
$out['manifest'] = ['pbx_version' => $manifest['pbx_version'], 'fpbx_db' => $manifest['fpbx_db'] ?? '',
  'fpbx_cdrdb' => $manifest['fpbx_cdrdb'] ?? ''];
$out['astdb_families'] = count($data['astdb']);

$files = array_merge(glob("$tmp/*.sql.gz"), glob("$tmp/*.sql"));
$out['sql_files'] = array_map('basename', $files);
$files || $fail('no SQL dump');
$moduleTables = $call('getModuleTables');
$dbh = $h->setupTempDb($files[0]);
$tables = $dbh->query("SELECT name FROM sqlite_master WHERE type = 'table'")->fetchAll(PDO::FETCH_COLUMN);
$out['tables'] = count($tables);
$out['unknown'] = [];
$out['modules'] = [];
foreach ($tables as $t) {
  if (isset($moduleTables[$t])) $out['modules'][$moduleTables[$t]][] = $t;
  else $out['unknown'][] = $t;
}
ksort($out['modules']);
$out['rows'] = [];
foreach ($want as $t) {
  $out['rows'][$t] = in_array($t, $tables) ? (int)$dbh->query("SELECT COUNT(*) FROM \"$t\"")->fetchColumn() : null;
}
(new Symfony\Component\Filesystem\Filesystem)->remove($tmp);
file_put_contents($json, json_encode($out, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
