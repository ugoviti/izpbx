<?php

// Load FreePBX bootstrap environment
require_once('/etc/freepbx.conf');

// Get the protocol
$protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";

// Get the host name
$host = $_SERVER['HTTP_HOST'];

// Combine the protocol and host to get the full URL
$http_host_with_protocol = $protocol . "://" . $host;

// Initialize a database connection
global $db;
$sql = "SELECT * FROM asterisk.contactmanager_groups WHERE id !='1'";

$PBOOK = isset($_GET["pb"]) ? (string)$_GET["pb"] : "";
$PHONE = isset($_GET["ph"]) ? (string)$_GET["ph"] : "";

// Execute the SQL statement
$res = $db->prepare($sql);
$res->execute();

$vendors = array_values(str_replace('.php', '', array_filter(scandir(__DIR__ . '/vendors'), function($file) { return pathinfo($file, PATHINFO_EXTENSION) === 'php'; })));

// accept only known vendors: blocks path traversal in the include below
if ($PHONE !== "" && !in_array($PHONE, $vendors, true)) {
  http_response_code(400);
  die('Error: unsupported phone vendor');
}

// escape values printed into HTML
function h($s) { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }

if ($PHONE == ""){
  if (DB::IsError($res)) {
    // Potentially clean this up so that it outputs pretty if not valid
    error_log( "There was an error attempting to query the extensions<br>($sql)<br>\n" . $res->getMessage() . "\n<br>\n");
  } else if ($PHONE == "") {
    echo "izPBX supported Phonebooks:<br><br>";
    foreach ($vendors as $vendor) {
    echo "- <a href=\"?ph=".h($vendor)."\">".h($vendor)."</a><br>";
    }
  }
} else if ($PBOOK == "") {
    $client = $res->fetchAll(PDO::FETCH_ASSOC);

    // $PHONE is a validated vendor name; the host comes from the request header, so escape it
    $P = h($PHONE);
    $H = h($http_host_with_protocol);
    echo "Phone: <b>".$P."</b>";
    echo "<br>";
    echo "<br>";
    echo "Menu: <br>";
    echo "- <a href=\"index.php?ph=".$P."&amp;pb=menu\">Menu</a> - configuration URL: <a href=\"".$P."/menu\">".$H."/pb/".$P."/menu</a>";
    echo "<br>";
    echo "<br>";
    echo "Addressbooks: <br>";
    echo "- <a href=\"index.php?ph=".$P."&amp;pb=ext\">Extensions</a> - configuration URL: <a href=\"".$P."/ext\">".$H."/pb/".$P."/ext</a>";
    echo "- <a href=\"index.php?ph=".$P."&amp;pb=contacts\">Contacts</a> - configuration URL: <a href=\"".$P."/ext\">".$H."/pb/".$P."/ext</a>";
    echo "<br>";

    # disable until found a better auto discovery method to avoid [XBOW-025-157] SQL Injection in Phonebook Directory Extension Path in izPBX project
    // foreach ($client as $client) {
    //   #echo "- <a href=".$PHONE.".php?pb=".$client["name"].">".$client["name"]."</a><br>";
    //   #echo "- <a href=".$PHONE."/".$client["name"].">".$client["name"]."</a><br>";
    //   echo "- <a href=index.php?ph=".$PHONE."&pb=".$client["name"].">".$client["name"]."</a> - configuration URL: <a href=".$PHONE."/".$client["name"].">".$http_host_with_protocol."/pb/".$PHONE."/".$client["name"]."</a>";
    // echo "<br>";
    // }
}

if (($PHONE != '') && ($PBOOK != '')){
  // $PHONE was validated against $vendors above
  include __DIR__ . "/vendors/".$PHONE.".php";
}

// clear the variables
$_SERVER['REQUEST_URI']="";
$PBOOK="";
$PHONE="";
?>
