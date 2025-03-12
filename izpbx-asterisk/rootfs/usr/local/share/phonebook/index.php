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

    echo "Phone: <b>".$_GET["ph"]."</b>";
    echo "<br>";
    echo "<br>";
    echo "Menu: <br>";
    //echo "- <a href=".$PHONE."/ext>Extensions</a><br>";
    echo "- <a href=index.php?ph=".$PHONE."&pb=menu>Menu</a> - configuration URL: <a href=".$PHONE."/menu>".$http_host_with_protocol."/pb/".$PHONE."/menu</a>";
    echo "<br>";
    echo "<br>";
    echo "Addressbooks: <br>";
    //echo "- <a href=".$PHONE."/ext>Extensions</a><br>";
    echo "- <a href=index.php?ph=".$PHONE."&pb=ext>Extensions</a> - configuration URL: <a href=".$PHONE."/ext>".$http_host_with_protocol."/pb/".$PHONE."/ext</a>";
    echo "- <a href=index.php?ph=".$PHONE."&pb=contacts>Contacts</a> - configuration URL: <a href=".$PHONE."/ext>".$http_host_with_protocol."/pb/".$PHONE."/ext</a>";
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
