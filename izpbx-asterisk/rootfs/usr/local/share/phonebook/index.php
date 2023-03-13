<?php

// Load FreePBX bootstrap environment
require_once('/etc/freepbx.conf');

// Initialize a database connection
global $db;
$sql = "SELECT * FROM asterisk.contactmanager_groups WHERE id !='1'";

$PBOOK=$_GET["pb"];
$PHONE=$_GET["ph"];

// Execute the SQL statement
$res = $db->prepare($sql);
$res->execute();

$vendors = str_replace('.php', '', array_filter(scandir('vendors'), function($file) { return pathinfo($file, PATHINFO_EXTENSION) === 'php'; }));

//print_r($vendors);

if ($PHONE == ""){
  if (DB::IsError($res)) {
    // Potentially clean this up so that it outputs pretty if not valid
    error_log( "There was an error attempting to query the extensions<br>($sql)<br>\n" . $res->getMessage() . "\n<br>\n");
  } else if ($PHONE == "") {
    echo "izPBX supported Phonebooks:<br><br>";
    foreach ($vendors as $vendor) {
    echo "- <a href=".$_SERVER['QUERY_STRING']."?ph=".$vendor.">".$vendor."</a><br>";
    }
  }
} else if ($PBOOK == "") {
    $client = $res->fetchAll(PDO::FETCH_ASSOC);

    // Get the protocol
    $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
 
    // Get the host name
    $host = $_SERVER['HTTP_HOST'];

    // Combine the protocol and host to get the full URL
    $http_host_with_protocol = $protocol . "://" . $host;

    echo "Selected Phone: <b>".$_GET["ph"]."</b>";
    echo "<br>";
    echo "<br>";
    echo "Available Address Books: <br>";
    //echo "- <a href=".$PHONE."/ext>Extensions</a><br>";
    echo "- <a href=index.php?ph=".$PHONE."&pb=ext>Extensions</a> - configuration URL: <a href=".$PHONE."/ext>".$http_host_with_protocol."/".$PHONE."/ext</a>";
    echo "<br>";

    foreach ($client as $client) {
      #echo "- <a href=".$PHONE.".php?pb=".$client["name"].">".$client["name"]."</a><br>";
      #echo "- <a href=".$PHONE."/".$client["name"].">".$client["name"]."</a><br>";
      echo "- <a href=index.php?ph=".$PHONE."&pb=".$client["name"].">".$client["name"]."</a> - configuration URL: <a href=".$PHONE."/".$client["name"].">".$http_host_with_protocol."/".$PHONE."/".$client["name"]."</a>";
    echo "<br>";
    }
}

if (($PHONE != '') && ($PBOOK != '')){
  if (file_exists("vendors/".$PHONE.".php")) {
    include "vendors/".$PHONE.".php";
  } else {
  die ('Errore: il file "vendors/'.$PHONE.'.php" non esiste.');
  }
}

// SVUOTO LE VARIABILI
$_SERVER['REQUEST_URI']="";
$PBOOK=$_GET[""];
$PHONE=$_GET[""];
?>

