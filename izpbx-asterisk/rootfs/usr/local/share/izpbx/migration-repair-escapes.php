<?php
// Values of FreePBX 16 damaged by the legacy restore of FreePBX 17, put back.
//
// The legacy restore (backup module, Handlers/Restore/Legacy.php) loads the
// mysqldump of FreePBX 16 into SQLite without undoing its escapes: a CR comes
// back as the two characters "\r", a quote as \", an apostrophe as \', a
// backslash as \\ (calendar events whose DTSTART cannot be read, "\r" in the
// outbound route emails, "\n" in the voicemail email body...).
//
// For every text column of the tables FreePBX 16 and 17 both have, each value
// of FreePBX 17 holding a backslash is compared with the database of FreePBX
// 16 (its dump loaded in another database): when the value with the dump
// escapes undone is a value of the same column in FreePBX 16, and the value
// itself is not, the FreePBX 16 value is written back. Values changed after
// the migration, and backslashes FreePBX 16 already had, are left alone.
//
//   php migration-repair-escapes.php OLD_DB NEW_DB [--apply]
// Connection from the environment: MYSQL_SERVER, APP_PORT_MYSQL, and the
// user/password in IZPBX_REPAIR_DBUSER / IZPBX_REPAIR_DBPASS.
// Output: one "FIX table.column: N row(s)" line per column to repair (written
// with --apply), "TABLES t1 t2..." with the tables to repair, and "LEFT
// table.column: N value(s)" for the backslashes left as they are.
[$old, $new] = [$argv[1] ?? '', $argv[2] ?? ''];
$apply = in_array('--apply', $argv, true);
if ($old === '' || $new === '') {
	fwrite(STDERR, "usage: migration-repair-escapes.php OLD_DB NEW_DB [--apply]\n");
	exit(2);
}
$dsn = sprintf('mysql:host=%s;port=%s;charset=utf8mb4', getenv('MYSQL_SERVER') ?: '127.0.0.1', getenv('APP_PORT_MYSQL') ?: '3306');
$db = new PDO($dsn, getenv('IZPBX_REPAIR_DBUSER'), getenv('IZPBX_REPAIR_DBPASS'),
	[PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_EMULATE_PREPARES => false]);

// the inverse of the escaping of mysqldump (mysql_real_escape_string)
function unescape(string $s): string {
	return preg_replace_callback('/\\\\(.)/s', function ($m) {
		switch ($m[1]) {
			case '0': return "\0";
			case 'n': return "\n";
			case 'r': return "\r";
			case 't': return "\t";
			case 'b': return "\x08";
			case 'Z': return "\x1a";
			default: return $m[1]; // \\ \' \" and any other character
		}
	}, $s);
}
function q(string $id): string { return '`' . str_replace('`', '``', $id) . '`'; }

$cols = $db->prepare("SELECT n.TABLE_NAME, n.COLUMN_NAME FROM information_schema.COLUMNS n
	JOIN information_schema.COLUMNS o ON o.TABLE_SCHEMA = ? AND o.TABLE_NAME = n.TABLE_NAME AND o.COLUMN_NAME = n.COLUMN_NAME
	WHERE n.TABLE_SCHEMA = ? AND n.DATA_TYPE IN ('char','varchar','tinytext','text','mediumtext','longtext','binary','varbinary','tinyblob','blob','mediumblob','longblob')
	ORDER BY n.TABLE_NAME, n.ORDINAL_POSITION");
$cols->execute([$old, $new]);
$tables = [];
$rc = 0;
foreach ($cols->fetchAll(PDO::FETCH_NUM) as [$t, $c]) {
	$sel = $db->query(sprintf('SELECT DISTINCT %1$s FROM %2$s.%3$s WHERE INSTR(%1$s, CHAR(92)) > 0', q($c), q($new), q($t)));
	$inOld = $db->prepare(sprintf('SELECT COUNT(*) FROM %2$s.%3$s WHERE %1$s = BINARY ?', q($c), q($old), q($t)));
	$upd = $db->prepare(sprintf('UPDATE %2$s.%3$s SET %1$s = ? WHERE %1$s = BINARY ?', q($c), q($new), q($t)));
	$fixed = 0; $left = 0;
	foreach ($sel->fetchAll(PDO::FETCH_COLUMN) as $v) {
		$inOld->execute([$v]);
		if ($inOld->fetchColumn() > 0) { continue; } // a backslash FreePBX 16 already had
		$u = unescape($v);
		$inOld->execute([$u]);
		if ($u === $v || $inOld->fetchColumn() == 0) { $left++; continue; }
		if ($apply) {
			$upd->execute([$u, $v]);
			$fixed += $upd->rowCount();
		} else {
			$cnt = $db->prepare(sprintf('SELECT COUNT(*) FROM %2$s.%3$s WHERE %1$s = BINARY ?', q($c), q($new), q($t)));
			$cnt->execute([$v]);
			$fixed += (int) $cnt->fetchColumn();
		}
	}
	if ($fixed > 0) { echo "FIX $t.$c: $fixed row(s)\n"; $tables[$t] = true; }
	if ($left > 0) { echo "LEFT $t.$c: $left value(s)\n"; }
}
echo 'TABLES ', implode(' ', array_keys($tables)), "\n";
exit($rc);
