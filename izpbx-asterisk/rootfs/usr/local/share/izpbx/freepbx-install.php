<?php
// izPBX: runs the FreePBX installer (current directory: the FreePBX tree)
// with the arguments given here plus --dbpass from the environment
// (IZPBX_INSTALL_DBPASS), so the database password is never on a command
// line visible in the process list (P3-21). Symfony reads $_SERVER['argv'].
// "install" starts with a shebang line, an error before "namespace" in an
// included file: a copy without it, next to it (its __DIR__ must not change).
$pass = getenv('IZPBX_INSTALL_DBPASS');
putenv('IZPBX_INSTALL_DBPASS');
$args = array_slice($_SERVER['argv'], 1);
if ($pass !== false && $pass !== '') {
    $args[] = '--dbpass=' . $pass;
}
$dir = getcwd();
$copy = $dir . '/.izpbx-install.php';
file_put_contents($copy, preg_replace('/^#![^\n]*\n/', '', file_get_contents($dir . '/install')));
register_shutdown_function(function () use ($copy) { @unlink($copy); });
$_SERVER['argv'] = array_merge(array($dir . '/install'), $args);
$_SERVER['argc'] = count($_SERVER['argv']);
require $copy;
